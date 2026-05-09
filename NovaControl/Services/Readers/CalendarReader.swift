// NovaControl — Calendar Reader (ICS feed)
// Written by Jordan Koch
// Reads events from an Office 365 ICS feed URL stored in Keychain.
// No EventKit entitlement needed — works via ICS URL polling.

import Foundation
import Security

actor CalendarReader {
    static let shared = CalendarReader()

    private var cache: (data: [CalendarEvent], fetchedAt: Date)?
    private let cacheTTL: TimeInterval = 900  // 15 minutes

    private init() {}

    // MARK: - Keychain

    private func icsURL() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "nova-calendar-ics-url",
            kSecAttrAccount: "nova",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let url = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !url.isEmpty else { return nil }
        return url
    }

    // MARK: - Fetch

    func events(days: Int = 7) async -> [CalendarEvent] {
        if let cache = cache, Date().timeIntervalSince(cache.fetchedAt) < cacheTTL {
            return filterEvents(cache.data, days: days)
        }
        let fresh = await fetchFresh()
        cache = (fresh, Date())
        return filterEvents(fresh, days: days)
    }

    func todayAndTomorrow() async -> (today: [CalendarEvent], tomorrow: [CalendarEvent]) {
        let all = await events(days: 2)
        let cal = Calendar.current
        let today    = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let dayAfter = cal.date(byAdding: .day, value: 2, to: today)!
        let todayEvents    = all.filter { $0.startDate >= today    && $0.startDate < tomorrow }
        let tomorrowEvents = all.filter { $0.startDate >= tomorrow && $0.startDate < dayAfter }
        return (todayEvents.sorted { $0.startDate < $1.startDate },
                tomorrowEvents.sorted { $0.startDate < $1.startDate })
    }

    func upcomingSoon(withinMinutes: Int = 30) async -> [CalendarEvent] {
        let now  = Date()
        let soon = now.addingTimeInterval(Double(withinMinutes) * 60)
        let all  = await events(days: 1)
        return all.filter { $0.startDate >= now && $0.startDate <= soon }
            .sorted { $0.startDate < $1.startDate }
    }

    // MARK: - ICS Parsing

    private func fetchFresh() async -> [CalendarEvent] {
        guard let urlString = icsURL(), let url = URL(string: urlString) else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let text = String(data: data, encoding: .utf8) else { return [] }
            return parseICS(text)
        } catch {
            NSLog("[CalendarReader] Fetch failed: \(error)")
            return []
        }
    }

    private func filterEvents(_ events: [CalendarEvent], days: Int) -> [CalendarEvent] {
        let cutoff = Date().addingTimeInterval(Double(days) * 86400)
        return events.filter { $0.startDate >= Calendar.current.startOfDay(for: Date()) && $0.startDate <= cutoff }
            .sorted { $0.startDate < $1.startDate }
    }

    private func parseICS(_ text: String) -> [CalendarEvent] {
        // Unfold ICS continuation lines
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .init(charactersIn: "\r"))
            if (trimmed.hasPrefix(" ") || trimmed.hasPrefix("\t")), !lines.isEmpty {
                lines[lines.count - 1] += trimmed.dropFirst()
            } else {
                lines.append(trimmed)
            }
        }

        var events: [CalendarEvent] = []
        var inEvent = false
        var current: [String: String] = [:]

        for line in lines {
            if line == "BEGIN:VEVENT" {
                inEvent = true; current = [:]
            } else if line == "END:VEVENT" {
                inEvent = false
                if let event = buildEvent(current) { events.append(event) }
            } else if inEvent, let colonIdx = line.firstIndex(of: ":") {
                let rawKey = String(line[..<colonIdx])
                let value  = String(line[line.index(after: colonIdx)...])
                let baseKey = rawKey.components(separatedBy: ";").first?.uppercased() ?? rawKey.uppercased()
                // Store TZID for datetime parsing
                if rawKey.uppercased().hasPrefix("DTSTART") || rawKey.uppercased().hasPrefix("DTEND") {
                    current[baseKey] = value
                } else {
                    current[baseKey] = value
                }
            }
        }
        return events
    }

    private func buildEvent(_ fields: [String: String]) -> CalendarEvent? {
        guard let summary = fields["SUMMARY"],
              let dtStart = fields["DTSTART"],
              let startDate = parseICSDate(dtStart) else { return nil }
        let endDate   = fields["DTEND"].flatMap { parseICSDate($0) }
        let uid       = fields["UID"] ?? UUID().uuidString
        let location  = fields["LOCATION"]
        let desc      = fields["DESCRIPTION"]?
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
        let allDay    = dtStart.count == 8 && !dtStart.contains("T")

        return CalendarEvent(
            id: uid,
            title: summary.replacingOccurrences(of: "\\,", with: ","),
            startDate: startDate,
            endDate: endDate,
            location: location,
            description: desc,
            isAllDay: allDay
        )
    }

    private func parseICSDate(_ raw: String) -> Date? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.contains(":") { s = String(s.split(separator: ":").last ?? Substring(s)) }

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")

        if s.hasSuffix("Z") {
            fmt.timeZone = TimeZone(identifier: "UTC")
            fmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        } else if s.contains("T") {
            fmt.timeZone = TimeZone.current
            fmt.dateFormat = "yyyyMMdd'T'HHmmss"
        } else {
            fmt.timeZone = TimeZone.current
            fmt.dateFormat = "yyyyMMdd"
        }
        return fmt.date(from: s)
    }
}

// MARK: - Model

struct CalendarEvent: Identifiable, Codable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date?
    let location: String?
    let description: String?
    let isAllDay: Bool

    var durationMinutes: Int? {
        guard let end = endDate else { return nil }
        return Int(end.timeIntervalSince(startDate) / 60)
    }

    var minutesUntilStart: Int {
        Int(startDate.timeIntervalSinceNow / 60)
    }
}
