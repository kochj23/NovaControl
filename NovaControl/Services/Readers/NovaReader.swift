// NovaControl — Nova / OpenClaw Reader
// Written by Jordan Koch
// Probes OpenClaw gateway, memory server, and cron status

import Foundation

actor NovaReader {
    static let shared = NovaReader()

    private let openclaw = "/opt/homebrew/bin/openclaw"
    private let gatewayURL = URL(string: "http://127.0.0.1:18789/health")!
    private let memoryURL  = URL(string: "http://127.0.0.1:18790/health")!

    func fetchStatus() async -> NovaStatus {
        async let gatewayResult = probeGateway()
        async let memoryResult  = probeMemory()
        async let cronResult    = fetchCrons()
        async let sessionResult = fetchSessionInfo()

        let (gateway, memory, crons, sessions) =
            await (gatewayResult, memoryResult, cronResult, sessionResult)

        return NovaStatus(
            gatewayOnline:     gateway.online,
            memoryServerOnline: memory.online,
            memoriesCount:     memory.count,
            currentModel:      sessions.model,
            activeSessions:    sessions.count,
            crons:             crons
        )
    }

    // MARK: - Gateway probe

    private func probeGateway() async -> (online: Bool, detail: String) {
        guard let (data, response) = try? await URLSession.shared.data(from: gatewayURL),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["ok"] as? Bool == true else {
            return (false, "unreachable")
        }
        return (true, "live")
    }

    // MARK: - Memory server probe

    private func probeMemory() async -> (online: Bool, count: Int) {
        guard let (data, response) = try? await URLSession.shared.data(from: memoryURL),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (false, 0)
        }
        let count = json["count"] as? Int ?? 0
        return (true, count)
    }

    // MARK: - Session info via openclaw status

    private func fetchSessionInfo() async -> (model: String, count: Int) {
        let output = runCommand(openclaw, args: ["status"])
        // Extract model from "default <model>" line and active session count
        var model = "unknown"
        var sessionCount = 0

        for line in output.components(separatedBy: "\n") {
            // Match "sessions N active · default <model>"
            if line.contains("active") && line.contains("default") {
                let parts = line.components(separatedBy: "·")
                if let sessionPart = parts.first {
                    let tokens = sessionPart.trimmingCharacters(in: .whitespaces)
                        .components(separatedBy: " ")
                    if let n = tokens.first.flatMap({ Int($0) }) {
                        sessionCount = n
                    }
                }
                if let modelPart = parts.last(where: { $0.contains("default") }) {
                    let m = modelPart.replacingOccurrences(of: "default", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if !m.isEmpty { model = m }
                }
            }
        }
        return (model, sessionCount)
    }

    // MARK: - Cron list

    func fetchCrons() async -> [NovaCronJob] {
        let output = runCommand(openclaw, args: ["cron", "list"])
        return parseCronOutput(output)
    }

    private func parseCronOutput(_ output: String) -> [NovaCronJob] {
        var jobs: [NovaCronJob] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Lines must be long enough to contain a UUID + data
            guard trimmed.count > 40 else { continue }

            // Must start with a valid UUID (36 chars: 8-4-4-4-12)
            let idPart = String(trimmed.prefix(36))
            guard UUID(uuidString: idPart) != nil else { continue }

            let rest = String(trimmed.dropFirst(37))

            // Split on 2+ consecutive spaces to extract columns:
            // [name, schedule, next, last, status, target, ...]
            let cols = rest.components(separatedBy: "  ")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            guard cols.count >= 5 else { continue }

            let status = cols[4].lowercased()
            guard ["ok", "error", "skipped"].contains(status) else { continue }

            jobs.append(NovaCronJob(
                id:       idPart,
                name:     cols[0],
                schedule: cols[1],
                nextRun:  cols[2],
                lastRun:  cols[3],
                status:   status,
                target:   cols.count > 5 ? cols[5] : "main"
            ))
        }
        return jobs
    }

    // MARK: - AI services health check

    func fetchAIServices() async -> [AIService] {
        let services: [(id: String, name: String, port: Int, path: String)] = [
            ("openclaw",  "OpenClaw Gateway",    18789, "/health"),
            ("memory",    "Nova Memory Server",  18790, "/health"),
            ("ollama",    "Ollama",              11434, "/api/tags"),
            ("swarmui",   "SwarmUI",              7801, "/API/Trex"),
            ("comfyui",   "ComfyUI",              7821, "/system_stats"),
        ]

        return await withTaskGroup(of: AIService.self) { group in
            for svc in services {
                group.addTask {
                    guard let url = URL(string: "http://127.0.0.1:\(svc.port)\(svc.path)") else {
                        return AIService(id: svc.id, name: svc.name, port: svc.port,
                                        isOnline: false, detail: "invalid url")
                    }
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 1.5
                    do {
                        let (data, response) = try await URLSession.shared.data(for: request)
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                        let online = (200...299).contains(statusCode)
                        var detail = online ? "online" : "http \(statusCode)"
                        // Enrich detail for known services
                        if svc.id == "memory", online,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let count = json["count"] as? Int {
                            detail = "\(count) memories"
                        }
                        if svc.id == "ollama", online,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let models = json["models"] as? [[String: Any]] {
                            detail = "\(models.count) models"
                        }
                        return AIService(id: svc.id, name: svc.name, port: svc.port,
                                        isOnline: online, detail: detail)
                    } catch {
                        return AIService(id: svc.id, name: svc.name, port: svc.port,
                                        isOnline: false, detail: "unreachable")
                    }
                }
            }
            var result: [AIService] = []
            for await svc in group { result.append(svc) }
            return result.sorted { $0.name < $1.name }
        }
    }

    // MARK: - Shell helper

    private func runCommand(_ cmd: String, args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cmd)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = Pipe() // discard stderr
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
