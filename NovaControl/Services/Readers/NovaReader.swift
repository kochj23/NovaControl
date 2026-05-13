// NovaControl — Nova Gateway v2 Reader
// Written by Jordan Koch
// Probes Nova Gateway v2 (pure Python asyncio), memory server, and scheduler status
// Note: OpenClaw (node.js, port 18789) was replaced by Nova Gateway v2 (port 18792) in May 2026

import Foundation

actor NovaReader {
    static let shared = NovaReader()

    // Nova Gateway v2 — pure Python asyncio replacement for OpenClaw
    private let gatewayURL = URL(string: "http://127.0.0.1:18792/health")!
    // Memory server binds to LAN IP
    private let memoryURL  = URL(string: "http://192.168.1.6:18790/health")!

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

    // MARK: - Session info via Gateway v2 health endpoint

    private func fetchSessionInfo() async -> (model: String, count: Int) {
        // Query Gateway v2 health for session count and model info
        guard let (data, response) = try? await URLSession.shared.data(from: gatewayURL),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ("qwen3:30b-a3b", 0)
        }
        let sessions = json["sessions"] as? Int ?? 0
        let version  = json["version"] as? String ?? "2.0.0"
        return ("qwen3:30b-a3b (gw \(version))", sessions)
    }

    // MARK: - Scheduler task list (replaces OpenClaw cron list)

    func fetchCrons() async -> [NovaCronJob] {
        // Query nova_scheduler HTTP API instead of deprecated openclaw cron list
        guard let url = URL(string: "http://192.168.1.6:37460/tasks"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        var jobs: [NovaCronJob] = []
        for (taskId, taskData) in json {
            guard let t = taskData as? [String: Any] else { continue }
            let schedule  = t["schedule"] as? String ?? ""
            let lastRun   = t["last_run"] as? Double ?? 0
            let nextRun   = t["next_run"] as? Double ?? 0
            let failures  = t["consecutive_failures"] as? Int ?? 0
            let exitCode  = t["last_exit_code"] as? Int ?? 0
            let enabled   = t["enabled"] as? Bool ?? true
            guard enabled else { continue }
            let status    = failures > 0 ? "error" : (exitCode == 0 ? "ok" : "error")
            let lastStr   = lastRun > 0 ? formatEpoch(lastRun) : "never"
            let nextStr   = nextRun > 0 ? formatEpoch(nextRun) : "—"
            jobs.append(NovaCronJob(id: taskId, name: taskId, schedule: schedule,
                                    nextRun: nextStr, lastRun: lastStr,
                                    status: status, target: "scheduler"))
        }
        return jobs.sorted { $0.name < $1.name }
    }

    private func formatEpoch(_ ts: Double) -> String {
        let date = Date(timeIntervalSince1970: ts)
        let fmt = DateFormatter()
        fmt.dateFormat = "MM-dd HH:mm"
        return fmt.string(from: date)
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

    // MARK: - Multi-Agent status

    func fetchAgents() async -> [AgentInfo] {
        // Query Gateway v2 health — agents are embedded in the Python gateway
        guard let url = URL(string: "http://127.0.0.1:18792/health") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return fallbackAgents()
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let agentsDict = json["agents"] as? [String: [String: Any]] {
                return parseAgentsResponse(agentsDict)
            }
            // Try parsing as array
            if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return json.compactMap { parseAgentDict($0) }
            }
            return fallbackAgents()
        } catch {
            return fallbackAgents()
        }
    }

    private func parseAgentsResponse(_ agents: [String: [String: Any]]) -> [AgentInfo] {
        return agents.compactMap { key, value -> AgentInfo? in
            let status = value["status"] as? String ?? "unknown"
            let model = value["model"] as? String ?? "unknown"
            let workspace = value["workspace_size"] as? Int ?? 0
            let channels = value["channels"] as? [String] ?? []
            let tasks = value["tasks_completed"] as? Int ?? 0
            let uptime = value["uptime_s"] as? Int ?? 0
            let lastError = value["last_error"] as? String

            return AgentInfo(
                id: key,
                name: key,
                status: status,
                model: model,
                workspaceSize: workspace,
                channels: channels,
                tasksCompleted: tasks,
                uptimeSeconds: uptime,
                lastError: lastError
            )
        }.sorted { $0.name < $1.name }
    }

    private func parseAgentDict(_ dict: [String: Any]) -> AgentInfo? {
        guard let id = dict["id"] as? String ?? dict["name"] as? String else { return nil }
        return AgentInfo(
            id: id,
            name: dict["name"] as? String ?? id,
            status: dict["status"] as? String ?? "unknown",
            model: dict["model"] as? String ?? "unknown",
            workspaceSize: dict["workspace_size"] as? Int ?? 0,
            channels: dict["channels"] as? [String] ?? [],
            tasksCompleted: dict["tasks_completed"] as? Int ?? 0,
            uptimeSeconds: dict["uptime_s"] as? Int ?? 0,
            lastError: dict["last_error"] as? String
        )
    }

    /// Fallback: return static agent info based on known Gateway v2 configuration
    private func fallbackAgents() -> [AgentInfo] {
        // Nova Gateway v2 agents — defined in nova_gateway_v2.py
        return [
            AgentInfo(id: "chat",     name: "chat",     status: "running",
                      model: "qwen3:30b-a3b",         workspaceSize: 8192,
                      channels: ["slack","discord","signal"], tasksCompleted: 0,
                      uptimeSeconds: 0, lastError: nil),
            AgentInfo(id: "research", name: "research", status: "running",
                      model: "openrouter/qwen3-235b",  workspaceSize: 65536,
                      channels: ["slack","discord","signal"], tasksCompleted: 0,
                      uptimeSeconds: 0, lastError: nil),
            AgentInfo(id: "home",     name: "home",     status: "running",
                      model: "qwen3:30b-a3b",          workspaceSize: 16384,
                      channels: ["slack","discord","signal"], tasksCompleted: 0,
                      uptimeSeconds: 0, lastError: nil),
        ]
    }

    // MARK: - AI services health check

    func fetchAIServices() async -> [AIService] {
        // Gateway v2 runs on 127.0.0.1:18792 (Python asyncio, replaced OpenClaw :18789)
        // Memory server and MLX server bind to LAN IP (192.168.1.6)
        let services: [(id: String, name: String, host: String, port: Int, path: String)] = [
            ("gateway_v2",  "Nova Gateway v2",      "127.0.0.1",   18792, "/health"),
            ("memory",      "Nova Memory Server",   "192.168.1.6", 18790, "/health"),
            ("memory_srch", "Memory /search",       "192.168.1.6", 18790, "/search?q=test&n=1"),
            ("ollama",      "Ollama",               "127.0.0.1",   11434, "/api/tags"),
            ("mlx",         "MLX Server",           "192.168.1.6",  5050, "/v1/models"),
            ("swarmui",     "SwarmUI",              "127.0.0.1",    7801, "/API/Trex"),
            ("bigbrother",  "Big Brother",          "192.168.1.6", 37461, "/bb/status"),
        ]

        return await withTaskGroup(of: AIService.self) { group in
            for svc in services {
                group.addTask {
                    guard let url = URL(string: "http://\(svc.host):\(svc.port)\(svc.path)") else {
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
                        if svc.id == "gateway_v2", online,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            let version  = json["version"] as? String ?? "2.0.0"
                            let sessions = json["sessions"] as? Int ?? 0
                            let uptime   = json["uptime_s"] as? Int ?? 0
                            detail = "v\(version) · \(sessions) sessions · \(uptime)s uptime"
                        }
                        if svc.id == "memory", online,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            let count = json["count"] as? Int ?? 0
                            let queue = json["queue_length"] as? Int ?? 0
                            detail = "\(count) memories · queue: \(queue)"
                        }
                        if svc.id == "memory_srch" {
                            detail = online ? "available" : "unavailable"
                        }
                        if svc.id == "ollama", online,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let models = json["models"] as? [[String: Any]] {
                            detail = "\(models.count) models"
                        }
                        if svc.id == "mlx", online,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let models = json["data"] as? [[String: Any]] {
                            detail = "\(models.count) model(s)"
                        }
                        if svc.id == "bigbrother", online,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            let down = (json["services_down"] as? [String] ?? []).count
                            detail = down == 0 ? "all systems healthy" : "\(down) service(s) down"
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
        // Note: services bind to 192.168.1.6 (LAN) except Ollama/Gateway v2 (127.0.0.1)
        let checks: [(id: String, name: String, port: Int)] = [
            ("postgresql",  "PostgreSQL",       5432),
            ("redis",       "Redis",            6379),
            ("ollama",      "Ollama",           11434),
            ("gateway_v2",  "Nova Gateway v2",  18792),
            ("memory",      "Memory Server",    18790),
            ("scheduler",   "Scheduler",        37460),
            ("bigbrother",  "Big Brother",      37461),
            ("openwebui",   "OpenWebUI",        3000),
            ("tinychat",    "TinyChat",         8000),
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
                case "gateway_v2":
                    if let url = URL(string: "http://127.0.0.1:18792/health"),
                       let (data, _) = try? await URLSession.shared.data(from: url),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let v = json["version"] as? String ?? "2.0.0"
                        let s = json["sessions"] as? Int ?? 0
                        detail = "v\(v) · \(s) sessions"
                    }
                case "memory":
                    if let url = URL(string: "http://192.168.1.6:18790/health"),
                       let (data, _) = try? await URLSession.shared.data(from: url),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let count = json["count"] as? Int {
                        detail = "\(count) memories"
                    }
                case "scheduler":
                    if let url = URL(string: "http://192.168.1.6:37460/status"),
                       let (data, _) = try? await URLSession.shared.data(from: url),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let total = json["tasks_total"] as? Int ?? 0
                        let runs  = json["total_runs"] as? Int ?? 0
                        detail = "\(total) tasks · \(runs) runs"
                    }
                case "bigbrother":
                    if let url = URL(string: "http://192.168.1.6:37461/bb/status"),
                       let (data, _) = try? await URLSession.shared.data(from: url),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let down = (json["services_down"] as? [String] ?? []).count
                        detail = down == 0 ? "all clear" : "\(down) down"
                    }
                case "redis":
                    let out = runCommand("/opt/homebrew/bin/redis-cli", args: ["-h", "192.168.1.6", "ping"])
                    detail = out.trimmingCharacters(in: .whitespacesAndNewlines) == "PONG" ? "PONG" : "no response"
                case "postgresql":
                    let out = runCommand("/opt/homebrew/opt/postgresql@17/bin/psql",
                                         args: ["-h", "192.168.1.6", "-d", "nova_memories", "-t", "-c", "SELECT 1"])
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
        // Check both loopback and LAN IP since services bind to different addresses
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
