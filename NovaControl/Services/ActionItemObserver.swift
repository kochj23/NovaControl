// ActionItemObserver.swift
// NovaControl — Auto-triggers workflows when action items change
//
// Polls OneOnOneReader every 60 seconds, detects new and completed
// action items, and fires the appropriate workflow triggers.
//
// Written by Jordan Koch.

import Foundation

@MainActor
final class ActionItemObserver {
    static let shared = ActionItemObserver()

    private let workflowEngine = WorkflowEngine.shared
    private let pollInterval: TimeInterval = 60

    private var timer: Timer?
    private var knownItemIDs: Set<UUID> = []
    private var isFirstPoll = true

    private init() {}

    // MARK: - Lifecycle

    func start() {
        NSLog("[ActionItemObserver] Starting — polling every \(Int(pollInterval))s")
        // Fire immediately on start, then repeat
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.poll()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        NSLog("[ActionItemObserver] Stopped")
    }

    // MARK: - Polling

    private func poll() {
        Task {
            await performPoll()
        }
    }

    private func performPoll() async {
        let reader = OneOnOneReader.shared

        guard await reader.isAvailable else {
            NSLog("[ActionItemObserver] OneOnOne data not available — skipping poll")
            return
        }

        let allItems = await reader.fetchActionItems()
        let openItems = allItems.filter { !$0.isCompleted }
        let currentIDs = Set(openItems.map { $0.id })

        if isFirstPoll {
            // Seed the known set on first poll — don't trigger workflows for existing items
            knownItemIDs = currentIDs
            isFirstPoll = false
            NSLog("[ActionItemObserver] Seeded with \(knownItemIDs.count) existing open action items")
            return
        }

        // Detect NEW items (in current but not in previously known)
        let newIDs = currentIDs.subtracting(knownItemIDs)
        for id in newIDs {
            guard let item = openItems.first(where: { $0.id == id }) else { continue }
            NSLog("[ActionItemObserver] New action item detected: \(item.title) (priority: \(item.priority))")
            let context: [String: String] = [
                "trigger": "action-item-observer",
                "title": item.title,
                "priority": item.priority,
                "assignee": item.assigneeId?.uuidString ?? "unassigned",
                "dueDate": item.dueDate.map { ISO8601DateFormatter().string(from: $0) } ?? "none"
            ]
            _ = await workflowEngine.run(workflowId: "action-item-to-slack", context: context)
        }

        // Detect COMPLETED items (in previously known but not in current open set)
        let completedIDs = knownItemIDs.subtracting(currentIDs)
        for id in completedIDs {
            NSLog("[ActionItemObserver] Action item completed or removed: \(id.uuidString)")
            // Note: action-item-to-jira workflow is disabled — just log for now
        }

        // Update known set
        knownItemIDs = currentIDs

        if !newIDs.isEmpty || !completedIDs.isEmpty {
            NSLog("[ActionItemObserver] Poll summary: +\(newIDs.count) new, -\(completedIDs.count) completed, \(currentIDs.count) total open")
        }
    }
}
