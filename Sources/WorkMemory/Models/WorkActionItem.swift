import Foundation

struct WorkActionItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var project: String
    var owner: String
    var dueDateText: String
    var evidence: String
    var sourceMemoryID: UUID?
    var sourceTitle: String
    var createdAt: Date
    var isCompleted: Bool

    init(
        id: UUID = UUID(),
        title: String,
        project: String = "",
        owner: String = "",
        dueDateText: String = "",
        evidence: String = "",
        sourceMemoryID: UUID? = nil,
        sourceTitle: String = "",
        createdAt: Date = Date(),
        isCompleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.owner = owner
        self.dueDateText = dueDateText
        self.evidence = evidence
        self.sourceMemoryID = sourceMemoryID
        self.sourceTitle = sourceTitle
        self.createdAt = createdAt
        self.isCompleted = isCompleted
    }

    var dedupeKey: String {
        "\(project)|\(title)"
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }
}

struct ActionItemSuggestion: Decodable {
    var title: String
    var project: String?
    var owner: String?
    var dueDateText: String?
    var evidence: String?
    var sourceIndex: Int?
}
