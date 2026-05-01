// ServiceModelsTests.swift — NovaControl
// Unit tests for all Codable service models.
// Written by Jordan Koch.

import XCTest
@testable import NovaControl

final class ServiceModelsTests: XCTestCase {

    // MARK: - ServiceStatus

    func testServiceStatusRawValues() {
        XCTAssertEqual(ServiceStatus.online.rawValue, "online")
        XCTAssertEqual(ServiceStatus.offline.rawValue, "offline")
        XCTAssertEqual(ServiceStatus.degraded.rawValue, "degraded")
    }

    // MARK: - ServiceInfo

    func testServiceInfoInit() {
        let info = ServiceInfo(id: "test", name: "Test", oldPort: 8080,
                               status: .online, summary: "Running fine")
        XCTAssertEqual(info.id, "test")
        XCTAssertEqual(info.name, "Test")
        XCTAssertEqual(info.oldPort, 8080)
        XCTAssertEqual(info.status, .online)
        XCTAssertEqual(info.summary, "Running fine")
        XCTAssertNotNil(info.lastUpdated)
    }

    // MARK: - Meeting

    func testMeetingDefaults() {
        let meeting = Meeting()
        XCTAssertNotEqual(meeting.id, UUID())
        XCTAssertEqual(meeting.title, "")
        XCTAssertTrue(meeting.attendeeNames.isEmpty)
        XCTAssertEqual(meeting.notes, "")
        XCTAssertTrue(meeting.actionItems.isEmpty)
        XCTAssertNil(meeting.summary)
    }

    func testMeetingWithValues() {
        let meeting = Meeting(title: "Sprint Retro", attendeeNames: ["Alice", "Bob"],
                              notes: "Good sprint", actionItems: [
                                ActionItem(title: "Deploy v2")
                              ], summary: "Productive meeting")
        XCTAssertEqual(meeting.title, "Sprint Retro")
        XCTAssertEqual(meeting.attendeeNames.count, 2)
        XCTAssertEqual(meeting.actionItems.count, 1)
        XCTAssertEqual(meeting.summary, "Productive meeting")
    }

    // MARK: - ActionItem

    func testActionItemDefaults() {
        let item = ActionItem(title: "Fix bug")
        XCTAssertEqual(item.title, "Fix bug")
        XCTAssertFalse(item.isCompleted)
        XCTAssertNil(item.assigneeId)
        XCTAssertNil(item.dueDate)
        XCTAssertEqual(item.priority, "medium")
    }

    func testActionItemHighPriority() {
        let item = ActionItem(title: "Critical fix", priority: "high")
        XCTAssertEqual(item.priority, "high")
    }

    // MARK: - Person

    func testPersonInit() {
        let person = Person(name: "Jordan")
        XCTAssertEqual(person.name, "Jordan")
        XCTAssertNil(person.email)
        XCTAssertNil(person.title)
        XCTAssertNil(person.department)
    }

    // MARK: - Goal

    func testGoalDefaults() {
        let personId = UUID()
        let goal = Goal(title: "Ship v2", personId: personId)
        XCTAssertEqual(goal.title, "Ship v2")
        XCTAssertEqual(goal.status, "active")
        XCTAssertEqual(goal.personId, personId)
    }

    // MARK: - ScannedDevice

    func testScannedDeviceDefaults() {
        let device = ScannedDevice(ipAddress: "192.168.1.1")
        XCTAssertEqual(device.ipAddress, "192.168.1.1")
        XCTAssertNil(device.hostname)
        XCTAssertNil(device.manufacturer)
        XCTAssertEqual(device.deviceType, "unknown")
        XCTAssertTrue(device.isWhitelisted)
        XCTAssertNil(device.userNotes)
    }

    // MARK: - ThreatFinding

    func testThreatFindingInit() {
        let threat = ThreatFinding(severity: "high", title: "Open SSH",
                                   description: "Port 22 exposed", affectedHost: "192.168.1.5")
        XCTAssertEqual(threat.severity, "high")
        XCTAssertEqual(threat.title, "Open SSH")
        XCTAssertEqual(threat.affectedHost, "192.168.1.5")
        XCTAssertNil(threat.affectedPort)
    }

    // MARK: - SyncJob

    func testSyncJobDefaults() {
        let job = SyncJob(name: "Backup Photos")
        XCTAssertEqual(job.name, "Backup Photos")
        XCTAssertTrue(job.sources.isEmpty)
        XCTAssertEqual(job.destination, "")
        XCTAssertTrue(job.isEnabled)
        XCTAssertNil(job.lastRun)
        XCTAssertNil(job.lastStatus)
        XCTAssertEqual(job.totalRuns, 0)
        XCTAssertEqual(job.successfulRuns, 0)
    }

    // MARK: - ExecutionHistoryEntry

    func testExecutionHistoryEntryDefaults() {
        let jobId = UUID()
        let entry = ExecutionHistoryEntry(jobId: jobId, jobName: "Backup")
        XCTAssertEqual(entry.jobId, jobId)
        XCTAssertEqual(entry.jobName, "Backup")
        XCTAssertEqual(entry.status, "success")
        XCTAssertEqual(entry.filesTransferred, 0)
        XCTAssertEqual(entry.bytesTransferred, 0)
        XCTAssertEqual(entry.duration, 0)
    }

    // MARK: - NewsArticle

    func testNewsArticleDefaults() {
        let article = NewsArticle(title: "Breaking News")
        XCTAssertEqual(article.title, "Breaking News")
        XCTAssertEqual(article.url, "")
        XCTAssertEqual(article.source, "")
        XCTAssertEqual(article.category, "general")
        XCTAssertFalse(article.isRead)
        XCTAssertFalse(article.isFavorite)
    }

    // MARK: - NovaCronJob

    func testNovaCronJobInit() {
        let job = NovaCronJob(id: "abc123", name: "Inbox Watcher", schedule: "*/5 * * * *",
                              nextRun: "5m", lastRun: "just now", status: "ok", target: "main")
        XCTAssertEqual(job.id, "abc123")
        XCTAssertEqual(job.name, "Inbox Watcher")
        XCTAssertEqual(job.status, "ok")
    }

    // MARK: - NovaStatus

    func testNovaStatusInit() {
        let status = NovaStatus(gatewayOnline: true, memoryServerOnline: true,
                                memoriesCount: 5000, currentModel: "qwen3-next:80b",
                                activeSessions: 2, crons: [])
        XCTAssertTrue(status.gatewayOnline)
        XCTAssertTrue(status.memoryServerOnline)
        XCTAssertEqual(status.memoriesCount, 5000)
        XCTAssertEqual(status.currentModel, "qwen3-next:80b")
        XCTAssertEqual(status.activeSessions, 2)
        XCTAssertTrue(status.crons.isEmpty)
    }

    // MARK: - AIService

    func testAIServiceInit() {
        let svc = AIService(id: "ollama", name: "Ollama", port: 11434,
                            isOnline: true, detail: "5 models")
        XCTAssertEqual(svc.id, "ollama")
        XCTAssertTrue(svc.isOnline)
        XCTAssertEqual(svc.port, 11434)
    }

    // MARK: - LocalLLM

    func testLocalLLMInit() {
        let llm = LocalLLM(id: "qwen3:30b", name: "qwen3:30b", backend: "ollama",
                           isLoaded: true, isAvailable: true, sizeGB: 16.5,
                           detail: "qwen2 · 30B · Q4_K_M")
        XCTAssertEqual(llm.id, "qwen3:30b")
        XCTAssertEqual(llm.backend, "ollama")
        XCTAssertTrue(llm.isLoaded)
        XCTAssertEqual(llm.sizeGB, 16.5)
    }

    func testLocalLLMNilSize() {
        let llm = LocalLLM(id: "mlx-server", name: "MLX Server", backend: "mlx",
                           isLoaded: true, isAvailable: true, sizeGB: nil, detail: "running")
        XCTAssertNil(llm.sizeGB)
    }

    // MARK: - TopologyConnection

    func testTopologyConnectionInit() {
        let conn = TopologyConnection(from: "NovaControl", to: "OneOnOne",
                                      type: "data_sync", active: true)
        XCTAssertEqual(conn.from, "NovaControl")
        XCTAssertEqual(conn.to, "OneOnOne")
        XCTAssertTrue(conn.active)
    }

    // MARK: - ManualHealthInput

    func testManualHealthInputDecoding() throws {
        let json = """
        {"memoryPressure": "high", "notes": "Running ML training"}
        """.data(using: .utf8)!
        let input = try JSONDecoder().decode(ManualHealthInput.self, from: json)
        XCTAssertEqual(input.memoryPressure, "high")
        XCTAssertEqual(input.notes, "Running ML training")
    }

    func testManualHealthInputNilFields() throws {
        let json = "{}".data(using: .utf8)!
        let input = try JSONDecoder().decode(ManualHealthInput.self, from: json)
        XCTAssertNil(input.memoryPressure)
        XCTAssertNil(input.notes)
    }

    // MARK: - NewsCategory

    func testNewsCategoryAllCases() {
        XCTAssertEqual(NewsCategory.allCases.count, 8)
    }

    func testNewsCategoryDisplayNames() {
        XCTAssertEqual(NewsCategory.technology.displayName, "Technology")
        XCTAssertEqual(NewsCategory.general.displayName, "General")
        XCTAssertEqual(NewsCategory.entertainment.displayName, "Entertainment")
    }

    // MARK: - Codable Round-Trip

    func testActionItemCodableRoundTrip() throws {
        let original = ActionItem(title: "Deploy", assigneeId: UUID(),
                                  isCompleted: false, dueDate: Date(), priority: "high")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ActionItem.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.priority, original.priority)
    }

    func testSyncJobCodableRoundTrip() throws {
        let original = SyncJob(name: "Photos", sources: ["/Users/test/Photos"],
                               destination: "/Volumes/NAS/Photos", isEnabled: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SyncJob.self, from: data)
        XCTAssertEqual(decoded.name, "Photos")
        XCTAssertEqual(decoded.sources, ["/Users/test/Photos"])
        XCTAssertEqual(decoded.destination, "/Volumes/NAS/Photos")
    }

    func testNewsArticleCodableRoundTrip() throws {
        let original = NewsArticle(title: "Test Article", url: "https://example.com",
                                   source: "TestSource", category: "technology")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(NewsArticle.self, from: data)
        XCTAssertEqual(decoded.title, "Test Article")
        XCTAssertEqual(decoded.category, "technology")
    }
}
