// NovaControl — OneOnOne Data Reader
// Written by Jordan Koch
// Reads from ~/Library/Application Support/OneOnOne/

import Foundation

actor OneOnOneReader {
    static let shared = OneOnOneReader()

    private var appSupportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OneOnOne")
    }

    private func load<T: Decodable>(_ filename: String, as type: T.Type) -> T? {
        let url = appSupportDir.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    func fetchMeetings() -> [Meeting] {
        return load("meetings.json", as: [Meeting].self) ?? []
    }

    func fetchActionItems() -> [ActionItem] {
        let meetings = fetchMeetings()
        return meetings.flatMap { $0.actionItems }
    }

    func fetchPeople() -> [Person] {
        return load("people.json", as: [Person].self) ?? []
    }

    func fetchGoals() -> [Goal] {
        return load("goals.json", as: [Goal].self) ?? []
    }
}
