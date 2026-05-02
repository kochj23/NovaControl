// NovaControl — HomeKit Reader (via Shortcuts CLI)
// Written by Jordan Koch
// macOS does not have native HomeKit.framework for menu bar apps.
// This reader uses the Shortcuts CLI to list and execute HomeKit scenes,
// replacing the need to keep HomeKitControl running for Nova.

import Foundation

actor HomeKitReader {
    static let shared = HomeKitReader()

    private var cachedScenes: [HomeKitScene] = []
    private var lastSceneFetch: Date = .distantPast
    private let cacheTTL: TimeInterval = 300 // 5 minutes

    // MARK: - Models

    struct HomeKitScene: Codable, Identifiable {
        let id: String
        let name: String
    }

    struct HomeKitAccessory: Codable, Identifiable {
        let id: String
        let name: String
        let room: String?
        let reachable: Bool
    }

    // MARK: - Scene Operations

    func fetchScenes(forceRefresh: Bool = false) async -> [HomeKitScene] {
        if !forceRefresh && Date().timeIntervalSince(lastSceneFetch) < cacheTTL && !cachedScenes.isEmpty {
            return cachedScenes
        }

        let output = await runShortcut("List HomeKit Scenes")
        guard let data = output.data(using: .utf8) else { return cachedScenes }

        // The Shortcut outputs a JSON array of scene names
        if let names = try? JSONDecoder().decode([String].self, from: data) {
            cachedScenes = names.map { HomeKitScene(id: $0.lowercased().replacingOccurrences(of: " ", with: "-"), name: $0) }
            lastSceneFetch = Date()
        } else {
            // Fallback: try line-separated output
            let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
            if !lines.isEmpty {
                cachedScenes = lines.map { HomeKitScene(id: $0.lowercased().replacingOccurrences(of: " ", with: "-"), name: $0) }
                lastSceneFetch = Date()
            }
        }

        return cachedScenes
    }

    func executeScene(name: String) async -> (Bool, String) {
        let scenes = await fetchScenes()
        guard let scene = scenes.first(where: { $0.name.lowercased() == name.lowercased() }) else {
            let available = scenes.map(\.name)
            return (false, "Scene '\(name)' not found. Available: \(available.joined(separator: ", "))")
        }

        let result = await runShortcut("Execute HomeKit Scene", input: scene.name)
        let success = !result.lowercased().contains("error") && !result.lowercased().contains("failed")
        return (success, success ? "Scene '\(scene.name)' executed" : "Failed: \(result)")
    }

    func fetchAccessories() async -> [HomeKitAccessory] {
        let output = await runShortcut("Nova HomeKit Status")
        guard let data = output.data(using: .utf8) else { return [] }

        if let accessories = try? JSONDecoder().decode([HomeKitAccessory].self, from: data) {
            return accessories
        }

        // Try parsing as array of dictionaries
        if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return json.compactMap { dict in
                guard let name = dict["name"] as? String else { return nil }
                return HomeKitAccessory(
                    id: (dict["id"] as? String) ?? UUID().uuidString,
                    name: name,
                    room: dict["room"] as? String,
                    reachable: (dict["reachable"] as? Bool) ?? true
                )
            }
        }

        return []
    }

    // MARK: - Shortcuts CLI

    private func runShortcut(_ name: String, input: String? = nil) async -> String {
        await withCheckedContinuation { continuation in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            proc.arguments = ["run", name, "--output-type", "public.plain-text"]

            let stdout = Pipe()
            let stderr = Pipe()
            proc.standardOutput = stdout
            proc.standardError = stderr

            if let input = input {
                let stdin = Pipe()
                proc.standardInput = stdin
                stdin.fileHandleForWriting.write(input.data(using: .utf8)!)
                stdin.fileHandleForWriting.closeFile()
            }

            proc.terminationHandler = { _ in
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            do {
                try proc.run()
            } catch {
                NSLog("[HomeKitReader] Failed to run shortcut '\(name)': \(error)")
                continuation.resume(returning: "error: \(error.localizedDescription)")
            }
        }
    }

    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: "/usr/bin/shortcuts")
    }
}
