// NovaControl — DataManager
// Written by Jordan Koch
// Aggregates all data sources and publishes to SwiftUI views

import Foundation
import Combine

@MainActor
class DataManager: ObservableObject {
    static let shared = DataManager()

    // OneOnOne
    @Published var meetings: [Meeting] = []
    @Published var actionItems: [ActionItem] = []
    @Published var people: [Person] = []
    @Published var goals: [Goal] = []

    // NMAPScanner
    @Published var devices: [ScannedDevice] = []
    @Published var threats: [ThreatFinding] = []

    // RsyncGUI
    @Published var syncJobs: [SyncJob] = []
    @Published var syncHistory: [ExecutionHistoryEntry] = []

    // System
    @Published var systemStats: SystemStats?
    @Published var topProcesses: [ProcessInfo] = []

    // News
    @Published var breakingNews: [NewsArticle] = []
    @Published var newsFavorites: [NewsArticle] = []

    // Nova / AI
    @Published var novaStatus: NovaStatus?
    @Published var aiServices: [AIService] = []
    @Published var mlxCodeInfo: MLXCodeInfo?
    @Published var localLLMs: [LocalLLM] = []
    @Published var novaSubsystems: [NovaSubsystem] = []
    @Published var novaAgents: [AgentInfo] = []
    @Published var novaStackBusy: Bool = false
    @Published var novaStackProgress: String = ""

    @Published var serviceStatuses: [ServiceInfo] = []
    @Published var lastRefresh: Date = Date()

    // Big Brother
    @Published var bbStatus: BBStatus?
    @Published var bbEvents: [BBHealEvent] = []
    @Published var bbServiceStates: [BBServiceState] = []
    @Published var bbAlive: Bool = false

    // UNAS Pro 8
    @Published var unasStatus: UNASStatus?

    // Synology NAS
    @Published var synologyStatus: SynologyStatus?

    private var refreshTimer: Timer?
    private var bbRefreshTimer: Timer?

    private init() {}

    func startRefreshing() {
        refresh()
        refreshBigBrother()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // Big Brother refreshes every 15s for responsive diagnostics
        bbRefreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshBigBrother() }
        }
    }

    func refreshBigBrother() {
        Task {
            async let alive   = BigBrotherReader.shared.isAlive()
            async let status  = BigBrotherReader.shared.fetchStatus()
            async let events  = BigBrotherReader.shared.fetchEvents(limit: 100)
            async let svcStates = BigBrotherReader.shared.fetchServiceStates()
            let (isAlive, st, evts, svcs) = await (alive, status, events, svcStates)
            await MainActor.run {
                self.bbAlive        = isAlive
                self.bbStatus       = st
                self.bbEvents       = evts
                self.bbServiceStates = svcs
            }
        }
    }

    func forceCheck() {
        Task { await BigBrotherReader.shared.forceCheck() }
    }

    func refresh() {
        Task {
            async let m     = OneOnOneReader.shared.fetchMeetings()
            async let a     = OneOnOneReader.shared.fetchActionItems()
            async let p     = OneOnOneReader.shared.fetchPeople()
            async let g     = OneOnOneReader.shared.fetchGoals()
            async let d     = NMAPReader.shared.fetchDevices()
            async let t     = NMAPReader.shared.fetchThreats()
            async let j     = RsyncReader.shared.fetchJobs()
            async let h     = RsyncReader.shared.fetchHistory()
            async let stats = SystemStatsReader.shared.fetchStats()
            async let procs = SystemStatsReader.shared.fetchProcesses()
            async let news  = NewsSummaryReader.shared.fetchBreaking()
            async let favs  = NewsSummaryReader.shared.fetchFavorites()
            async let nova  = NovaReader.shared.fetchStatus()
            async let ai    = NovaReader.shared.fetchAIServices()
            async let mlx   = MLXCodeReader.shared.fetchStatus()
            async let llms  = NovaReader.shared.fetchLocalLLMs()
            async let subs  = NovaReader.shared.fetchSubsystems()
            async let agents = NovaReader.shared.fetchAgents()
            async let unas  = UNASReader.shared.fetchStatus()
            async let syno  = SynologyReader.shared.fetchStatus()

            let (meetings, actions, persons, goals, devs, threats, jobs, history,
                 sysStats, processes, articles, favorites, novaStatus, aiServices, mlxInfo, localLLMs,
                 subsystems, agentList, unasData, synoData) =
                await (m, a, p, g, d, t, j, h, stats, procs, news, favs, nova, ai, mlx, llms, subs, agents, unas, syno)

            await MainActor.run {
                self.meetings      = meetings
                self.actionItems   = actions
                self.people        = persons
                self.goals         = goals
                self.devices       = devs
                self.threats       = threats
                self.syncJobs      = jobs
                self.syncHistory   = history
                self.systemStats   = sysStats
                self.topProcesses  = processes
                self.breakingNews  = articles
                self.newsFavorites = favorites
                self.novaStatus    = novaStatus
                self.aiServices    = aiServices
                self.mlxCodeInfo   = mlxInfo
                self.localLLMs     = localLLMs
                self.novaSubsystems = subsystems
                self.novaAgents    = agentList
                self.unasStatus    = unasData
                self.synologyStatus = synoData
                self.lastRefresh   = Date()
                self.updateServiceStatuses()
            }
        }
    }

    private func updateServiceStatuses() {
        let cpu = systemStats.map { Int($0.cpuUser + $0.cpuSystem) }
        let ram = systemStats.map { $0.memUsedGB }

        var statuses: [ServiceInfo] = [
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

        // Synology NAS service card
        if let syno = synologyStatus {
            statuses.append(ServiceInfo(
                id: "synology",
                name: "Synology RS1221+",
                oldPort: 0,
                status: syno.isHealthy ? .online : (syno.problemCount > 0 ? .degraded : .online),
                summary: "CPU \(Int(syno.cpuPct))% · RAM \(Int(syno.ramPct))% · \(syno.volumeStatus)"
            ))
        }

        // UNAS Pro 8 service card
        if let unas = unasStatus {
            let st = unas.storage
            statuses.append(ServiceInfo(
                id: "unas",
                name: "UNAS Pro 8",
                oldPort: 0,
                status: unas.isHealthy ? .online : .degraded,
                summary: "\(st.usedPctFormatted) used · \(st.freeFormatted) free of \(st.totalFormatted)"
            ))
        }

        // Nova gateway service card
        if let nova = novaStatus {
            statuses.append(ServiceInfo(
                id: "nova",
                name: "Nova",
                oldPort: 18789,
                status: nova.gatewayOnline ? .online : .offline,
                summary: nova.gatewayOnline
                    ? "\(nova.memoriesCount) memories · \(nova.crons.filter { $0.status == "error" }.count) cron errors"
                    : "gateway offline"
            ))
        }

        serviceStatuses = statuses
    }

    // MARK: - Nova Stack Control

    func novaStackAction(_ action: NovaStackAction) {
        guard !novaStackBusy else { return }
        novaStackBusy = true
        novaStackProgress = ""
        let cmd: String
        switch action {
        case .start:   cmd = "start"
        case .stop:    cmd = "stop"
        case .restart: cmd = "restart"
        }
        Task {
            _ = await NovaReader.shared.runServiceAction(cmd) { line in
                Task { @MainActor in
                    self.novaStackProgress = line
                }
            }
            try? await Task.sleep(for: .seconds(2))
            refresh()
            await MainActor.run {
                novaStackBusy = false
                novaStackProgress = ""
            }
        }
    }

    /// Look up person name by ID
    func personName(for id: UUID?) -> String? {
        guard let id = id else { return nil }
        return people.first(where: { $0.id == id })?.name
    }
}
