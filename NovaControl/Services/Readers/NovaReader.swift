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
            ("openclaw",    "OpenClaw Gateway",     18789, "/health"),
            ("memory",      "Nova Memory Server",   18790, "/health"),
            ("memory_srch", "Memory /search",       18790, "/search?q=test&n=1"),
            ("ollama",      "Ollama",               11434, "/api/tags"),
            ("novanextgen", "Nova-NextGen",         34750, "/api/ai/backends"),
            ("swarmui",     "SwarmUI",               7801, "/API/Trex"),
            ("comfyui",     "ComfyUI",               7821, "/system_stats"),
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
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            let count = json["count"] as? Int ?? 0
                            let queue = json["queue_length"] as? Int ?? 0
                            detail = "\(count) memories · queue: \(queue)"
                        }
                        if svc.id == "memory_srch" {
                            detail = online ? "available" : "unavailable"
                        }
                        if svc.id == "novanextgen", online,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let backends = json["backends"] as? [[String: Any]] {
                            let activeCount = backends.filter { $0["available"] as? Bool == true }.count
                            detail = "\(activeCount)/\(backends.count) backends active"
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

    // MARK: - Local LLM health

    func fetchLocalLLMs() async -> [LocalLLM] {
        async let ollamaResult = fetchOllamaLLMs()
        async let mlxResult    = fetchMLXLLM()

        let (ollamaModels, mlxModels) = await (ollamaResult, mlxResult)
        return (ollamaModels + mlxModels).sorted { $0.name < $1.name }
    }

    private func fetchOllamaLLMs() async -> [LocalLLM] {
        let tagsURL = URL(string: "http://127.0.0.1:11434/api/tags")!
        let psURL   = URL(string: "http://127.0.0.1:11434/api/ps")!

        // Fetch available models
        var tagsRequest = URLRequest(url: tagsURL)
        tagsRequest.timeoutInterval = 3
        var psRequest = URLRequest(url: psURL)
        psRequest.timeoutInterval = 3

        var available: [[String: Any]] = []
        var running: Set<String> = []

        // Get all available models
        if let (data, resp) = try? await URLSession.shared.data(for: tagsRequest),
           let http = resp as? HTTPURLResponse, http.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let models = json["models"] as? [[String: Any]] {
            available = models
        }

        // Get currently loaded/running models
        if let (data, resp) = try? await URLSession.shared.data(for: psRequest),
           let http = resp as? HTTPURLResponse, http.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let models = json["models"] as? [[String: Any]] {
            for m in models {
                if let name = m["name"] as? String {
                    running.insert(name)
                }
            }
        }

        return available.compactMap { model -> LocalLLM? in
            guard let name = model["name"] as? String else { return nil }
            let sizeBytes = model["size"] as? Double ?? 0
            let sizeGB = sizeBytes / 1_073_741_824

            // Extract detail from model info
            var details: [String] = []
            if let detail = model["details"] as? [String: Any] {
                if let family = detail["family"] as? String { details.append(family) }
                if let params = detail["parameter_size"] as? String { details.append(params) }
                if let quant = detail["quantization_level"] as? String { details.append(quant) }
            }

            return LocalLLM(
                id: name,
                name: name,
                backend: "ollama",
                isLoaded: running.contains(name),
                isAvailable: true,
                sizeGB: sizeGB > 0 ? sizeGB : nil,
                detail: details.isEmpty ? "ollama" : details.joined(separator: " · ")
            )
        }
    }

    private func fetchMLXLLM() async -> [LocalLLM] {
        let url = URL(string: "http://127.0.0.1:5050/v1/models")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 3

        guard let (data, resp) = try? await URLSession.shared.data(for: request),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else {
            // Try a simple health check — if server is up but no /v1/models, show as single entry
            let healthURL = URL(string: "http://127.0.0.1:5050/health")!
            var healthReq = URLRequest(url: healthURL)
            healthReq.timeoutInterval = 2
            if let (_, resp) = try? await URLSession.shared.data(for: healthReq),
               let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return [LocalLLM(id: "mlx-server", name: "MLX Server", backend: "mlx",
                                 isLoaded: true, isAvailable: true, sizeGB: nil, detail: "running")]
            }
            return []
        }

        return models.compactMap { m -> LocalLLM? in
            guard let id = m["id"] as? String else { return nil }
            return LocalLLM(id: "mlx-\(id)", name: id, backend: "mlx",
                            isLoaded: true, isAvailable: true, sizeGB: nil, detail: "mlx")
        }
    }

    // MARK: - Subsystem Control

    private let novaServices = NSHomeDirectory() + "/.openclaw/scripts/nova-services.sh"

    func startAllServices() async -> String {
        return runCommand(novaServices, args: ["start"])
    }

    func stopAllServices() async -> String {
        return runCommand(novaServices, args: ["stop"])
    }

    func restartAllServices() async -> String {
        return runCommand(novaServices, args: ["restart"])
    }

    func runServiceAction(_ action: String, onProgress: @escaping (String) -> Void) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: novaServices)
        process.arguments = [action]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return false
        }

        let handle = pipe.fileHandleForReading

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var buffer = Data()
                while process.isRunning || handle.availableData.count > 0 {
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        Thread.sleep(forTimeInterval: 0.1)
                        continue
                    }
                    buffer.append(chunk)

                    while let range = buffer.range(of: Data("\n".utf8)) {
                        let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                        buffer.removeSubrange(buffer.startIndex...range.lowerBound)
                        if let line = String(data: lineData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                           !line.isEmpty {
                            let clean = self.stripAnsi(line)
                            DispatchQueue.main.async { onProgress(clean) }
                        }
                    }
                }
                process.waitUntilExit()
                cont.resume()
            }
        }

        return process.terminationStatus == 0
    }

    private func stripAnsi(_ str: String) -> String {
        str.replacingOccurrences(
            of: "\\e\\[[0-9;]*m|\\[\\d+;?\\d*m",
            with: "",
            options: .regularExpression
        )
    }

    func fetchSubsystems() async -> [NovaSubsystem] {
        let checks: [(id: String, name: String, port: Int)] = [
            ("postgresql", "PostgreSQL", 5432),
            ("redis", "Redis", 6379),
            ("ollama", "Ollama", 11434),
            ("gateway", "OpenClaw Gateway", 18789),
            ("memory", "Memory Server", 18790),
            ("openwebui", "OpenWebUI", 3000),
            ("tinychat", "TinyChat", 8000),
        ]

        var results: [NovaSubsystem] = []
        for svc in checks {
            let running = isPortListening(svc.port)
            var detail = running ? "port \(svc.port)" : "stopped"

            if running {
                switch svc.id {
                case "ollama":
                    if let url = URL(string: "http://127.0.0.1:11434/api/tags"),
                       let (data, _) = try? await URLSession.shared.data(from: url),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let models = json["models"] as? [[String: Any]] {
                        detail = "\(models.count) models"
                    }
                case "memory":
                    if let url = URL(string: "http://127.0.0.1:18790/health"),
                       let (data, _) = try? await URLSession.shared.data(from: url),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let count = json["count"] as? Int {
                        detail = "\(count) memories"
                    }
                case "redis":
                    let out = runCommand("/opt/homebrew/bin/redis-cli", args: ["ping"])
                    detail = out.trimmingCharacters(in: .whitespacesAndNewlines) == "PONG" ? "PONG" : "no response"
                case "postgresql":
                    let out = runCommand("/opt/homebrew/opt/postgresql@17/bin/psql",
                                         args: ["-h", "127.0.0.1", "-d", "nova_memories", "-t", "-c", "SELECT 1"])
                    detail = out.contains("1") ? "nova_memories OK" : "query failed"
                default:
                    break
                }
            }

            results.append(NovaSubsystem(id: svc.id, name: svc.name, port: svc.port,
                                          isRunning: running, detail: detail))
        }
        return results
    }

    private func isPortListening(_ port: Int) -> Bool {
        let output = runCommand("/usr/sbin/lsof", args: ["-ti", "tcp:\(port)", "-sTCP:LISTEN"])
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
