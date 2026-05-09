// NovaControl — Plex Media Server Reader
// Written by Jordan Koch
// Proxies Plex API via Keychain token — Nova never needs to know the token or URL.

import Foundation
import Security

actor PlexReader {
    static let shared = PlexReader()

    private let plexURL = "http://192.168.1.10:32400"
    private var cachedToken: String?

    private init() {}

    // MARK: - Keychain

    private func plexToken() -> String? {
        if let cached = cachedToken { return cached }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "nova-plex-token",
            kSecAttrAccount: "nova",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else { return nil }
        cachedToken = token
        return token
    }

    // MARK: - HTTP

    private func plexRequest(path: String, query: [String: String] = [:]) async throws -> Data {
        guard let token = plexToken() else {
            throw PlexError.noToken
        }
        var components = URLComponents(string: plexURL + path)!
        var queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        queryItems.append(URLQueryItem(name: "X-Plex-Token", value: token))
        components.queryItems = queryItems
        var request = URLRequest(url: components.url!, timeoutInterval: 10)
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    // MARK: - API

    /// Currently playing sessions
    func nowPlaying() async -> [[String: Any]] {
        guard let data = try? await plexRequest(path: "/status/sessions"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let container = json["MediaContainer"] as? [String: Any],
              let metadata = container["Metadata"] as? [[String: Any]] else { return [] }
        return metadata.map { item in
            var out: [String: Any] = [:]
            out["title"]       = item["title"] as? String ?? ""
            out["grandparentTitle"] = item["grandparentTitle"] as? String ?? ""
            out["type"]        = item["type"] as? String ?? ""
            out["viewOffset"]  = item["viewOffset"] as? Int ?? 0
            out["duration"]    = item["duration"] as? Int ?? 0
            if let user = (item["User"] as? [String: Any]) {
                out["user"] = user["title"] as? String ?? ""
            }
            if let player = (item["Player"] as? [String: Any]) {
                out["device"] = player["title"] as? String ?? ""
                out["state"]  = player["state"] as? String ?? ""
            }
            return out
        }
    }

    /// On-deck items (continue watching)
    func onDeck(limit: Int = 10) async -> [[String: Any]] {
        guard let data = try? await plexRequest(path: "/library/onDeck", query: ["X-Plex-Container-Size": String(limit)]),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let container = json["MediaContainer"] as? [String: Any],
              let metadata = container["Metadata"] as? [[String: Any]] else { return [] }
        return metadata.prefix(limit).map { simplifyMetadata($0) }
    }

    /// Recently added items
    func recentlyAdded(limit: Int = 10) async -> [[String: Any]] {
        guard let data = try? await plexRequest(path: "/library/recentlyAdded", query: ["X-Plex-Container-Size": String(limit)]),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let container = json["MediaContainer"] as? [String: Any],
              let metadata = container["Metadata"] as? [[String: Any]] else { return [] }
        return metadata.prefix(limit).map { simplifyMetadata($0) }
    }

    /// Library stats summary
    func librarySummary() async -> [String: Any] {
        guard let data = try? await plexRequest(path: "/library/sections"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let container = json["MediaContainer"] as? [String: Any],
              let sections = container["Directory"] as? [[String: Any]] else {
            return ["error": "Could not fetch library sections"]
        }
        var summary: [[String: Any]] = []
        for section in sections {
            let key  = section["key"] as? String ?? ""
            let type = section["type"] as? String ?? ""
            let name = section["title"] as? String ?? ""
            guard !key.isEmpty else { continue }
            if let countData = try? await plexRequest(path: "/library/sections/\(key)/all", query: ["X-Plex-Container-Size": "0"]),
               let countJson = try? JSONSerialization.jsonObject(with: countData) as? [String: Any],
               let mc = countJson["MediaContainer"] as? [String: Any] {
                let total = mc["totalSize"] as? Int ?? mc["size"] as? Int ?? 0
                summary.append(["name": name, "type": type, "count": total])
            }
        }
        return ["libraries": summary, "server": plexURL]
    }

    /// Server identity/reachability
    func serverStatus() async -> [String: Any] {
        guard let data = try? await plexRequest(path: "/identity"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let container = json["MediaContainer"] as? [String: Any] else {
            // Fallback: just check if port is reachable
            if let _ = try? await plexRequest(path: "/library/sections") {
                return ["online": true, "version": "unknown", "friendlyName": "Plex", "machineIdentifier": ""]
            }
            return ["online": false]
        }
        return [
            "online": true,
            "version": container["version"] as? String ?? "",
            "friendlyName": container["friendlyName"] as? String ?? "",
            "machineIdentifier": container["machineIdentifier"] as? String ?? ""
        ]
    }

    // MARK: - Helpers

    private func simplifyMetadata(_ item: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        out["title"]            = item["title"] as? String ?? ""
        out["type"]             = item["type"] as? String ?? ""
        out["year"]             = item["year"] as? Int
        out["thumb"]            = item["thumb"] as? String
        out["grandparentTitle"] = item["grandparentTitle"] as? String ?? ""
        out["summary"]          = (item["summary"] as? String ?? "").prefix(200).description
        out["addedAt"]          = item["addedAt"] as? Int
        out["viewCount"]        = item["viewCount"] as? Int ?? 0
        return out
    }
}

enum PlexError: Error {
    case noToken
    case networkError(String)
}
