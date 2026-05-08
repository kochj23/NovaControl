// NovaControl — BigBrotherReader
// Written by Jordan Koch
// Reads from Big Brother diagnostics API on port 37461

import Foundation

final class BigBrotherReader {
    static let shared = BigBrotherReader()
    private let base = "http://127.0.0.1:37461"

    private init() {}

    // MARK: - Status

    func fetchStatus() async -> BBStatus? {
        guard let url = URL(string: "\(base)/bb/status") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode(BBStatus.self, from: data)
        } catch {
            NSLog("[BigBrotherReader] status fetch failed: \(error)")
            return nil
        }
    }

    // MARK: - Events

    func fetchEvents(limit: Int = 100) async -> [BBHealEvent] {
        guard let url = URL(string: "\(base)/bb/events?n=\(limit)") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let rawArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return []
            }
            return rawArray.map { BBHealEvent(from: $0) }
        } catch {
            NSLog("[BigBrotherReader] events fetch failed: \(error)")
            return []
        }
    }

    // MARK: - Services

    func fetchServiceStates() async -> [BBServiceState] {
        guard let url = URL(string: "\(base)/bb/services") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
                return []
            }
            return dict.map { name, info in
                BBServiceState(
                    id: name,
                    name: name,
                    up: info["up"] as? Bool ?? true,
                    lastError: info["last_error"] as? String,
                    restarts: info["restarts"] as? Int ?? 0
                )
            }.sorted { $0.name < $1.name }
        } catch {
            NSLog("[BigBrotherReader] services fetch failed: \(error)")
            return []
        }
    }

    // MARK: - Force Check

    func forceCheck() async {
        guard let url = URL(string: "\(base)/bb/force-check") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Is Big Brother alive?

    func isAlive() async -> Bool {
        guard let url = URL(string: "\(base)/bb/status") else { return false }
        do {
            let (_, resp) = try await URLSession.shared.data(from: url)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
