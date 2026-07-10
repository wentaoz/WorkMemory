import Foundation

struct MemoryProject: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
    }
}

struct MemoryChunk: Identifiable, Codable, Hashable {
    let id: UUID
    var memoryID: UUID
    var ordinal: Int
    var locator: String
    var content: String

    init(id: UUID = UUID(), memoryID: UUID, ordinal: Int, locator: String, content: String) {
        self.id = id
        self.memoryID = memoryID
        self.ordinal = ordinal
        self.locator = locator
        self.content = content
    }
}

enum MemoryRecordKind: String, Codable {
    case memory
    case activity
    case chunk
    case action
}

struct RecordReference: Codable, Hashable {
    var kind: MemoryRecordKind
    var id: UUID
}

struct MemoryCitation: Identifiable, Codable, Hashable {
    let id: UUID
    var marker: String
    var title: String
    var excerpt: String
    var locator: String
    var reference: RecordReference

    init(
        id: UUID = UUID(),
        marker: String,
        title: String,
        excerpt: String,
        locator: String = "",
        reference: RecordReference
    ) {
        self.id = id
        self.marker = marker
        self.title = title
        self.excerpt = excerpt
        self.locator = locator
        self.reference = reference
    }
}

enum SummaryRunKind: String, Codable {
    case daily
    case selected
    case web
    case document
}

enum SummaryRunStatus: String, Codable {
    case waiting
    case running
    case completed
    case failed
    case cancelled
}

struct SummaryRun: Identifiable, Codable, Hashable {
    let id: UUID
    var kind: SummaryRunKind
    var status: SummaryRunStatus
    var rangeStart: Date
    var rangeEnd: Date
    var progress: Double
    var sourceCount: Int
    var resultMemoryID: UUID?
    var errorMessage: String
    var createdAt: Date
    var updatedAt: Date
}

struct SearchableRecord: Identifiable, Hashable {
    var id: String { "\(reference.kind.rawValue):\(reference.id.uuidString)" }
    var reference: RecordReference
    var title: String
    var content: String
    var createdAt: Date
    var locator: String
    var contextSummary: String
    var projectID: UUID?
    var isPinned: Bool
}

struct RankedMemoryResult: Identifiable, Hashable {
    var id: String { record.id }
    var record: SearchableRecord
    var score: Double
}

struct AskMemoryTurn: Identifiable, Hashable {
    let id: UUID
    var question: String
    var answer: String
    var citations: [MemoryCitation]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        question: String,
        answer: String,
        citations: [MemoryCitation],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.question = question
        self.answer = answer
        self.citations = citations
        self.createdAt = createdAt
    }
}
