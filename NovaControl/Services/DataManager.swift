// NovaControl — DataManager
// Written by Jordan Koch
// Aggregates all data sources and publishes to SwiftUI views

import Foundation
import Combine

@MainActor
class DataManager: ObservableObject {
    static let shared = DataManager()

    @Published var meetings: [Meeting] = []
    @Published var actionItems: [ActionItem] = []
    @Published var people: [Person] = []
    @Published var devices: [ScannedDevice] = []
    @Published var threats: [ThreatFinding] = []
    @Published var syncJobs: [SyncJob] = []
    @Published var syncHistory: [ExecutionHistoryEntry] = []
    @Published var systemStats: SystemStats?
    @Published var topProcesses: [ProcessInfo] = []
    @Published var breakingNews: [NewsArticle] = []
    @Published var serviceStatuses: [ServiceInfo] = []
    @Published var lastRefresh: Date = Date()

    private var refreshTimer: Timer?

    private init() {}

    func startRefreshing() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        Task {
            async let m = OneOnOneReader.shared.fetchMeetings()
            async let a = OneOnOneReader.shared.fetchActionItems()
            async let p = OneOnOneReader.shared.fetchPeople()
            async let d = NMAPReader.shared.fetchDevices()
            async let t = NMAPReader.shared.fetchThreats()
            async let j = RsyncReader.shared.fetchJobs()
            async let h = RsyncReader.shared.fetchHistory()
            async let stats = SystemStatsReader.shared.fetchStats()
            async let procs = SystemStatsReader.shared.fetchProcesses()
            async let news = NewsSummaryReader.shared.fetchBreaking()

            let (meetings, actions, persons, devs, threats, jobs, history, sysStats, processes, articles) =
                await (m, a, p, d, t, j, h, stats, procs, news)

            await MainActor.run {
                self.meetings = meetings
                self.actionItems = actions
                self.people = persons
                self.devices = devs
                self.threats = threats
                self.syncJobs = jobs
                self.syncHistory = history
                self.systemStats = sysStats
                self.topProcesses = processes
                self.breakingNews = articles
                self.lastRefresh = Date()
                self.updateServiceStatuses()
            }
        }
    }

    private func updateServiceStatuses() {
        let cpu = systemStats.map { Int($0.cpuUser + $0.cpuSystem) }
        let ram = systemStats.map { $0.memUsedGB }

        serviceStatuses = [
            ServiceInfo(
                id: "oneonone",
                name: "OneOnOne",
                oldPort: 37421,
                status: meetings.isEmpty ? .degraded : .online,
                summary: "\(meetings.count) meetings · \(actionItems.filter { !$0.isCompleted }.count) open actions"
            ),
            ServiceInfo(
                id: "nmap",
                name: "NMAPScanner",
                oldPort: 37423,
                status: devices.isEmpty ? .degraded : .online,
                summary: "\(devices.count) devices · \(threats.count) threats"
            ),
            ServiceInfo(
                id: "rsync",
                name: "RsyncGUI",
                oldPort: 37424,
                status: .online,
                summary: "\(syncJobs.filter { $0.isEnabled }.count)/\(syncJobs.count) jobs enabled"
            ),
            ServiceInfo(
                id: "topgui",
                name: "TopGUI",
                oldPort: 37443,
                status: systemStats != nil ? .online : .degraded,
                summary: cpu.map { "CPU \($0)% · RAM \(String(format: "%.1f", ram ?? 0))GB" } ?? "Loading..."
            ),
            ServiceInfo(
                id: "news",
                name: "News Summary",
                oldPort: 37438,
                status: .online,
                summary: "\(breakingNews.count) unread stories"
            ),
        ]
    }

    /// Look up person name by ID
    func personName(for id: UUID?) -> String? {
        guard let id = id else { return nil }
        return people.first(where: { $0.id == id })?.name
    }
}
