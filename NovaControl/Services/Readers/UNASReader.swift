// NovaControl — UniFi UNAS Pro 8 Reader
// Written by Jordan Koch
// Reads status from ~/.openclaw/workspace/state/nova_unas_status.json
// Written by nova_unas_monitor.py every 5 minutes.

import Foundation

actor UNASReader {
    static let shared = UNASReader()

    private let statusFile: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".openclaw/workspace/state/nova_unas_status.json")
    }()

    private init() {}

    // MARK: - Public API

    func fetchStatus() async -> UNASStatus? {
        guard let data = try? Data(contentsOf: statusFile) else { return nil }
        return try? JSONDecoder().decode(UNASStatus.self, from: data)
    }

    func isHealthy() async -> Bool {
        guard let status = await fetchStatus() else { return false }
        return status.storage.status == "healthy"
    }
}

// MARK: - Models

struct UNASStatus: Codable {
    let device: UNASDevice
    let storage: UNASStorage
    let shares: [UNASShare]
    let timestamp: Double

    var isHealthy: Bool { storage.status == "healthy" }
    var lastUpdated: Date { Date(timeIntervalSince1970: timestamp) }
    var staleness: TimeInterval { Date().timeIntervalSince(lastUpdated) }
    var isStale: Bool { staleness > 600 } // >10 min = stale
}

struct UNASDevice: Codable {
    let model: String
    let name: String
    let mac: String
    let state: String
    let cloudConnected: Bool
    let hasInternet: Bool

    enum CodingKeys: String, CodingKey {
        case model, name, mac, state
        case cloudConnected = "cloud_connected"
        case hasInternet = "has_internet"
    }
}

struct UNASStorage: Codable {
    let status: String
    let totalBytes: Int
    let usedBytes: Int
    let freeBytes: Int
    let usedPct: Double
    let totalTb: Double
    let freeTb: Double
    let needsMoreDisk: Bool

    enum CodingKeys: String, CodingKey {
        case status
        case totalBytes = "total_bytes"
        case usedBytes = "used_bytes"
        case freeBytes = "free_bytes"
        case usedPct = "used_pct"
        case totalTb = "total_tb"
        case freeTb = "free_tb"
        case needsMoreDisk = "needs_more_disk"
    }

    var usedPctFormatted: String { String(format: "%.1f%%", usedPct) }
    var totalFormatted: String { String(format: "%.2f TB", totalTb) }
    var freeFormatted: String { String(format: "%.2f TB", freeTb) }
    var isWarning: Bool { usedPct >= 80 }
    var isCritical: Bool { usedPct >= 90 }
}

struct UNASShare: Codable, Identifiable {
    let id: String
    let name: String
    let status: String
    let usedBytes: Int
    let usedTb: Double
    let encryption: String
    let quota: Int

    enum CodingKeys: String, CodingKey {
        case id, name, status, encryption, quota
        case usedBytes = "used_bytes"
        case usedTb = "used_tb"
    }

    var usedFormatted: String { String(format: "%.2f TB", usedTb) }
    var isEncrypted: Bool { encryption != "unencrypted" }
}
