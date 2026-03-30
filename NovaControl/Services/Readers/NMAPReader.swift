// NovaControl — NMAPScanner Data Reader
// Written by Jordan Koch
// Reads NMAPScanner data from UserDefaults and runs live scans

import Foundation

actor NMAPReader {
    static let shared = NMAPReader()

    func fetchDevices() -> [ScannedDevice] {
        guard let data = UserDefaults.standard.data(forKey: "com.digitalnoise.nmapscanner.devices"),
              let devices = try? JSONDecoder().decode([ScannedDevice].self, from: data) else {
            return []
        }
        return devices
    }

    func fetchThreats() -> [ThreatFinding] {
        guard let data = UserDefaults.standard.data(forKey: "com.digitalnoise.nmapscanner.threats"),
              let threats = try? JSONDecoder().decode([ThreatFinding].self, from: data) else {
            return []
        }
        return threats
    }

    func runScan(ip: String) async -> String {
        // Run nmap directly — requires nmap installed via homebrew
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["nmap", "-sn", ip]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "nmap launch failed: \(error.localizedDescription)"
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? "Scan failed"
    }
}
