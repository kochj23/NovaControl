// NovaControl — Unified HTTP API Server
// Written by Jordan Koch
// Port 37400 · binds to 127.0.0.1 only
// Replaces: OneOnOne (37421), NMAPScanner (37423), RsyncGUI (37424), TopGUI (37443), News Summary (37438)

import Foundation
import Network

final class NovaAPIServer {
    static let shared = NovaAPIServer()

    private var listener: NWListener?
    private let port: UInt16 = 37400
    private let queue = DispatchQueue(label: "net.digitalnoise.novacontrol.apiserver", qos: .utility)

    private init() {}

    // MARK: - Start / Stop

    func start() {
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host("127.0.0.1"),
                port: NWEndpoint.Port(rawValue: port)!
            )
            listener = try NWListener(using: params)
        } catch {
            NSLog("[NovaAPIServer] Failed to create listener: \(error)")
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                NSLog("[NovaAPIServer] Listening on 127.0.0.1:37400")
            case .failed(let error):
                NSLog("[NovaAPIServer] Listener failed: \(error)")
            default:
                break
            }
        }

        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(from: connection)
    }

    private func receiveRequest(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                self.processRequest(data: data, connection: connection)
            }
            if isComplete || error != nil {
                connection.cancel()
            }
        }
    }

    private func processRequest(data: Data, connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendError(connection: connection, status: 400, message: "Bad request")
            return
        }

        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendError(connection: connection, status: 400, message: "Bad request")
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendError(connection: connection, status: 400, message: "Bad request")
            return
        }

        let method = String(parts[0]).uppercased()
        let rawPath = String(parts[1])

        // Parse path and query string
        let pathComponents = rawPath.split(separator: "?", maxSplits: 1)
        let path = String(pathComponents[0])
        var queryParams: [String: String] = [:]
        if pathComponents.count > 1 {
            let queryString = String(pathComponents[1])
            for pair in queryString.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    queryParams[String(kv[0])] = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                }
            }
        }

        // Parse body for POST requests
        var body: Data?
        if method == "POST", let bodyRange = requestString.range(of: "\r\n\r\n") {
            let bodyStart = requestString.distance(from: requestString.startIndex, to: bodyRange.upperBound)
            if let bodyData = requestString.dropFirst(bodyStart).data(using: .utf8) {
                body = bodyData
            }
        }

        // Route the request
        route(method: method, path: path, query: queryParams, body: body, connection: connection)
    }

    // MARK: - Router

    private func route(method: String, path: String, query: [String: String], body: Data?, connection: NWConnection) {
        // Add CORS headers support
        if method == "OPTIONS" {
            sendResponse(connection: connection, status: 200, body: Data())
            return
        }

        Task {
            let (status, responseBody) = await self.handleRoute(method: method, path: path, query: query, body: body)
            self.sendJSON(connection: connection, status: status, json: responseBody)
        }
    }

    private func handleRoute(method: String, path: String, query: [String: String], body: Data?) async -> (Int, Any) {
        // GET /api/status
        if method == "GET" && path == "/api/status" {
            return await handleStatus()
        }

        // OneOnOne routes
        if method == "GET" && path == "/api/oneonone/meetings" {
            return await handleMeetings(query: query)
        }
        if method == "GET" && path == "/api/oneonone/actionitems" {
            return await handleActionItems(query: query)
        }
        if method == "GET" && path == "/api/oneonone/people" {
            return await handlePeople()
        }

        // NMAP routes
        if method == "GET" && path == "/api/nmap/devices" {
            return await handleDevices()
        }
        if method == "GET" && path == "/api/nmap/threats" {
            return await handleThreats()
        }
        if method == "POST" && path == "/api/nmap/scan" {
            return await handleNmapScan(body: body)
        }

        // Rsync routes
        if method == "GET" && path == "/api/rsync/jobs" {
            return await handleRsyncJobs()
        }
        if method == "GET" && path == "/api/rsync/history" {
            return await handleRsyncHistory()
        }
        // POST /api/rsync/jobs/{id}/run
        if method == "POST" && path.hasPrefix("/api/rsync/jobs/") && path.hasSuffix("/run") {
            let idString = path
                .replacingOccurrences(of: "/api/rsync/jobs/", with: "")
                .replacingOccurrences(of: "/run", with: "")
            return await handleRsyncRun(jobIdString: idString)
        }

        // System routes
        if method == "GET" && path == "/api/system/stats" {
            return await handleSystemStats()
        }
        if method == "GET" && path == "/api/system/processes" {
            return await handleProcesses()
        }

        // News routes
        if method == "GET" && path == "/api/news/breaking" {
            return await handleBreakingNews()
        }
        if method == "GET" && path.hasPrefix("/api/news/articles/") {
            let category = path.replacingOccurrences(of: "/api/news/articles/", with: "")
            return await handleNewsByCategory(category: category)
        }

        return (404, ["error": "Route not found", "path": path])
    }

    // MARK: - Route Handlers

    private func handleStatus() async -> (Int, Any) {
        let dm = await DataManager.shared
        let statuses = await dm.serviceStatuses
        let lastRefresh = await dm.lastRefresh

        // Probe Nova memory gateway
        var novaMemoryStatus = "unreachable"
        if let url = URL(string: "http://127.0.0.1:18790/health") {
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    novaMemoryStatus = "online"
                }
            } catch {
                // unreachable — leave as is
            }
        }

        let statusDicts = statuses.map { s -> [String: Any] in
            [
                "id": s.id,
                "name": s.name,
                "oldPort": s.oldPort,
                "status": s.status.rawValue,
                "summary": s.summary,
                "lastUpdated": ISO8601DateFormatter().string(from: s.lastUpdated)
            ]
        }

        return (200, [
            "novacontrol": "online",
            "port": 37400,
            "lastRefresh": ISO8601DateFormatter().string(from: lastRefresh),
            "novaMemoryGateway": novaMemoryStatus,
            "services": statusDicts
        ])
    }

    private func handleMeetings(query: [String: String]) async -> (Int, Any) {
        let meetings = await OneOnOneReader.shared.fetchMeetings()
        let limit = Int(query["limit"] ?? "20") ?? 20
        let limited = Array(meetings.sorted { $0.date > $1.date }.prefix(limit))
        return (200, encodable(limited))
    }

    private func handleActionItems(query: [String: String]) async -> (Int, Any) {
        let items = await OneOnOneReader.shared.fetchActionItems()
        let filtered: [ActionItem]
        if let completedStr = query["completed"] {
            let wantCompleted = completedStr.lowercased() == "true"
            filtered = items.filter { $0.isCompleted == wantCompleted }
        } else {
            filtered = items
        }
        return (200, encodable(filtered))
    }

    private func handlePeople() async -> (Int, Any) {
        let people = await OneOnOneReader.shared.fetchPeople()
        return (200, encodable(people))
    }

    private func handleDevices() async -> (Int, Any) {
        let devices = await NMAPReader.shared.fetchDevices()
        return (200, encodable(devices))
    }

    private func handleThreats() async -> (Int, Any) {
        let threats = await NMAPReader.shared.fetchThreats()
        return (200, encodable(threats))
    }

    private func handleNmapScan(body: Data?) async -> (Int, Any) {
        guard let body = body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: String],
              let ip = json["ip"] else {
            return (400, ["error": "Request body must contain {\"ip\": \"...\"}"])
        }
        let result = await NMAPReader.shared.runScan(ip: ip)
        return (200, ["ip": ip, "result": result])
    }

    private func handleRsyncJobs() async -> (Int, Any) {
        let jobs = await RsyncReader.shared.fetchJobs()
        return (200, encodable(jobs))
    }

    private func handleRsyncHistory() async -> (Int, Any) {
        let history = await RsyncReader.shared.fetchHistory()
        return (200, encodable(history))
    }

    private func handleRsyncRun(jobIdString: String) async -> (Int, Any) {
        guard let jobId = UUID(uuidString: jobIdString) else {
            return (400, ["error": "Invalid job ID: \(jobIdString)"])
        }
        let result = await RsyncReader.shared.runJob(jobId)
        return (200, ["jobId": jobIdString, "output": result])
    }

    private func handleSystemStats() async -> (Int, Any) {
        let stats = await SystemStatsReader.shared.fetchStats()
        return (200, encodable(stats))
    }

    private func handleProcesses() async -> (Int, Any) {
        let processes = await SystemStatsReader.shared.fetchProcesses()
        return (200, encodable(processes))
    }

    private func handleBreakingNews() async -> (Int, Any) {
        let articles = await NewsSummaryReader.shared.fetchBreaking()
        return (200, encodable(articles))
    }

    private func handleNewsByCategory(category: String) async -> (Int, Any) {
        let articles = await NewsSummaryReader.shared.fetchByCategory(category)
        return (200, encodable(articles))
    }

    // MARK: - Response Helpers

    private func encodable<T: Encodable>(_ value: T) -> Any {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(value),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return ["error": "Encoding failed"]
        }
        return json
    }

    private func sendJSON(connection: NWConnection, status: Int, json: Any) {
        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
            sendResponse(connection: connection, status: status, body: data, contentType: "application/json")
        } catch {
            sendError(connection: connection, status: 500, message: "JSON serialization error")
        }
    }

    private func sendError(connection: NWConnection, status: Int, message: String) {
        let json: [String: Any] = ["error": message]
        sendJSON(connection: connection, status: status, json: json)
    }

    private func sendResponse(connection: NWConnection, status: Int, body: Data,
                               contentType: String = "application/json") {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        default:  statusText = "Unknown"
        }

        let headers = [
            "HTTP/1.1 \(status) \(statusText)",
            "Content-Type: \(contentType); charset=utf-8",
            "Content-Length: \(body.count)",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")

        var responseData = headers.data(using: .utf8)!
        responseData.append(body)

        connection.send(content: responseData, completion: .contentProcessed { error in
            if let error = error {
                NSLog("[NovaAPIServer] Send error: \(error)")
            }
            connection.cancel()
        })
    }
}
