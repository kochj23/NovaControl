// NovaControl — Synology NAS Reader
// Written by Jordan Koch
// Reads ~/.openclaw/workspace/state/nova_synology_state.json
// Written by nova_synology_monitor.py every 30 minutes.

import Foundation

actor SynologyReader {
    static let shared = SynologyReader()

    private let statusFile: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".openclaw/workspace/state/nova_synology_state.json")
    }()

    private init() {}

    func fetchStatus() async -> SynologyStatus? {
        guard let data = try? Data(contentsOf: statusFile),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let cpu    = dict["cpu_pct"] as? Double ?? (dict["cpu_pct"] as? Int).map { Double($0) } ?? 0
        let ram    = dict["ram_pct"] as? Double ?? (dict["ram_pct"] as? Int).map { Double($0) } ?? 0
        let model  = dict["model"] as? String ?? "Synology"
        let fw     = dict["firmware"] as? String ?? ""
        let issues = dict["problem_count"] as? Int ?? 0
        let volStr = dict["volumes"] as? String ?? ""
        let netTx  = dict["net_tx_bps"] as? Double ?? 0
        let netRx  = dict["net_rx_bps"] as? Double ?? 0
        let diskR  = dict["disk_read_bps"] as? Double ?? 0
        let diskW  = dict["disk_write_bps"] as? Double ?? 0
        let ts     = dict["last_check"] as? String ?? ""

        let volStatus: String = {
            if volStr.contains("crashed") || volStr.contains("error") { return "degraded" }
            if volStr.contains("normal") { return "healthy" }
            return "unknown"
        }()

        return SynologyStatus(
            model: model,
            firmware: fw,
            cpuPct: cpu,
            ramPct: ram,
            netTxBps: netTx,
            netRxBps: netRx,
            diskReadBps: diskR,
            diskWriteBps: diskW,
            volumeStatus: volStatus,
            problemCount: issues,
            lastCheck: ts
        )
    }

    func isHealthy() async -> Bool {
        guard let s = await fetchStatus() else { return false }
        return s.problemCount == 0 && s.volumeStatus == "healthy"
    }
}

// MARK: - Model

struct SynologyStatus {
    let model: String
    let firmware: String
    let cpuPct: Double
    let ramPct: Double
    let netTxBps: Double
    let netRxBps: Double
    let diskReadBps: Double
    let diskWriteBps: Double
    let volumeStatus: String
    let problemCount: Int
    let lastCheck: String

    var isHealthy: Bool { problemCount == 0 && volumeStatus != "degraded" }
    var cpuColor: StatusColor { cpuPct > 80 ? .critical : cpuPct > 50 ? .warning : .ok }
    var ramColor: StatusColor { ramPct > 90 ? .critical : ramPct > 75 ? .warning : .ok }

    var netTxFormatted: String { _fmtBps(netTxBps) }
    var netRxFormatted: String { _fmtBps(netRxBps) }
    var diskReadFormatted: String  { _fmtBps(diskReadBps) }
    var diskWriteFormatted: String { _fmtBps(diskWriteBps) }

    enum StatusColor { case ok, warning, critical }
}

private func _fmtBps(_ bps: Double) -> String {
    guard bps > 0 else { return "0 B/s" }
    if bps >= 1_000_000 { return String(format: "%.1f MB/s", bps / 1_000_000) }
    if bps >= 1_000     { return String(format: "%.0f KB/s", bps / 1_000) }
    return String(format: "%.0f B/s", bps)
}
