// NovaControl — Service Models
// Written by Jordan Koch

import Foundation

// MARK: - Service Status

enum ServiceStatus: String, Codable {
    case online
    case offline
    case degraded
}

struct ServiceInfo: Identifiable, Codable {
    let id: String
    let name: String
    let oldPort: Int
    let status: ServiceStatus
    let lastUpdated: Date
    let summary: String

    init(id: String, name: String, oldPort: Int, status: ServiceStatus, summary: String) {
        self.id = id
        self.name = name
        self.oldPort = oldPort
        self.status = status
        self.lastUpdated = Date()
        self.summary = summary
    }
}

// MARK: - OneOnOne Models

struct Meeting: Identifiable, Codable {
    let id: UUID
    let date: Date
    let attendeeNames: [String]
    let notes: String
    let actionItems: [ActionItem]
    let summary: String?

    init(id: UUID = UUID(), date: Date = Date(), attendeeNames: [String] = [],
         notes: String = "", actionItems: [ActionItem] = [], summary: String? = nil) {
        self.id = id
        self.date = date
        self.attendeeNames = attendeeNames
        self.notes = notes
        self.actionItems = actionItems
        self.summary = summary
    }
}

struct ActionItem: Identifiable, Codable {
    let id: UUID
    let title: String
    let assigneeId: UUID?
    let isCompleted: Bool
    let dueDate: Date?
    let priority: String

    init(id: UUID = UUID(), title: String, assigneeId: UUID? = nil,
         isCompleted: Bool = false, dueDate: Date? = nil, priority: String = "medium") {
        self.id = id
        self.title = title
        self.assigneeId = assigneeId
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.priority = priority
    }
}

struct Person: Identifiable, Codable {
    let id: UUID
    let name: String
    let email: String?
    let title: String?
    let department: String?

    init(id: UUID = UUID(), name: String, email: String? = nil,
         title: String? = nil, department: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.title = title
        self.department = department
    }
}

struct Goal: Identifiable, Codable {
    let id: UUID
    let title: String
    let status: String
    let personId: UUID

    init(id: UUID = UUID(), title: String, status: String = "active", personId: UUID) {
        self.id = id
        self.title = title
        self.status = status
        self.personId = personId
    }
}

// MARK: - NMAPScanner Models

struct ScannedDevice: Identifiable, Codable {
    let id: UUID
    let ipAddress: String
    let hostname: String?
    let manufacturer: String?
    let deviceType: String
    let lastSeen: Date
    let isWhitelisted: Bool
    let userNotes: String?

    init(id: UUID = UUID(), ipAddress: String, hostname: String? = nil,
         manufacturer: String? = nil, deviceType: String = "unknown",
         lastSeen: Date = Date(), isWhitelisted: Bool = true, userNotes: String? = nil) {
        self.id = id
        self.ipAddress = ipAddress
        self.hostname = hostname
        self.manufacturer = manufacturer
        self.deviceType = deviceType
        self.lastSeen = lastSeen
        self.isWhitelisted = isWhitelisted
        self.userNotes = userNotes
    }
}

struct ThreatFinding: Identifiable, Codable {
    let id: UUID
    let severity: String
    let title: String
    let description: String
    let affectedHost: String
    let affectedPort: String?
    let detectedAt: Date

    init(id: UUID = UUID(), severity: String, title: String, description: String,
         affectedHost: String, affectedPort: String? = nil, detectedAt: Date = Date()) {
        self.id = id
        self.severity = severity
        self.title = title
        self.description = description
        self.affectedHost = affectedHost
        self.affectedPort = affectedPort
        self.detectedAt = detectedAt
    }
}

// MARK: - RsyncGUI Models

struct SyncJob: Identifiable, Codable {
    let id: UUID
    let name: String
    let sources: [String]
    let destination: String
    let isEnabled: Bool
    let lastRun: Date?
    let lastStatus: String?
    let totalRuns: Int
    let successfulRuns: Int

    init(id: UUID = UUID(), name: String, sources: [String] = [],
         destination: String = "", isEnabled: Bool = true,
         lastRun: Date? = nil, lastStatus: String? = nil,
         totalRuns: Int = 0, successfulRuns: Int = 0) {
        self.id = id
        self.name = name
        self.sources = sources
        self.destination = destination
        self.isEnabled = isEnabled
        self.lastRun = lastRun
        self.lastStatus = lastStatus
        self.totalRuns = totalRuns
        self.successfulRuns = successfulRuns
    }
}

struct ExecutionHistoryEntry: Identifiable, Codable {
    let id: UUID
    let jobId: UUID
    let jobName: String
    let timestamp: Date
    let status: String
    let filesTransferred: Int
    let bytesTransferred: Int
    let duration: Double

    init(id: UUID = UUID(), jobId: UUID, jobName: String, timestamp: Date = Date(),
         status: String = "success", filesTransferred: Int = 0,
         bytesTransferred: Int = 0, duration: Double = 0) {
        self.id = id
        self.jobId = jobId
        self.jobName = jobName
        self.timestamp = timestamp
        self.status = status
        self.filesTransferred = filesTransferred
        self.bytesTransferred = bytesTransferred
        self.duration = duration
    }
}

// MARK: - System Stats Models

struct ProcessInfo: Identifiable, Codable {
    var id: Int { pid }
    let pid: Int
    let command: String
    let cpuPercent: Double
    let memPercent: Double
    let user: String
}

struct SystemStats: Codable {
    let cpuUser: Double
    let cpuSystem: Double
    let memUsedGB: Double
    let memTotalGB: Double
    let diskReadMBs: Double
    let diskWriteMBs: Double
    let uptime: TimeInterval
}

// MARK: - News Models

struct NewsArticle: Identifiable, Codable {
    let id: UUID
    let title: String
    let url: String
    let source: String
    let category: String
    let publishedAt: Date
    let isRead: Bool
    let isFavorite: Bool

    init(id: UUID = UUID(), title: String, url: String = "", source: String = "",
         category: String = "general", publishedAt: Date = Date(),
         isRead: Bool = false, isFavorite: Bool = false) {
        self.id = id
        self.title = title
        self.url = url
        self.source = source
        self.category = category
        self.publishedAt = publishedAt
        self.isRead = isRead
        self.isFavorite = isFavorite
    }
}

enum NewsCategory: String, CaseIterable, Codable {
    case general
    case technology
    case business
    case science
    case health
    case sports
    case entertainment
    case politics

    var displayName: String {
        switch self {
        case .general: return "General"
        case .technology: return "Technology"
        case .business: return "Business"
        case .science: return "Science"
        case .health: return "Health"
        case .sports: return "Sports"
        case .entertainment: return "Entertainment"
        case .politics: return "Politics"
        }
    }
}
