import Foundation

enum WorkActionStatus: String, Codable, CaseIterable {
    case open
    case deferred
    case completed
}

enum WorkActionPriority: String, Codable, CaseIterable {
    case low
    case normal
    case high
    case urgent
}

struct WorkActionItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var project: String
    var owner: String
    var dueDateText: String
    var dueDate: Date?
    var priority: WorkActionPriority
    var status: WorkActionStatus
    var evidence: String
    var sourceMemoryID: UUID?
    var sourceTitle: String
    var createdAt: Date
    var updatedAt: Date
    var reminderIdentifier: String?

    var isCompleted: Bool {
        get { status == .completed }
        set { status = newValue ? .completed : .open }
    }

    init(
        id: UUID = UUID(),
        title: String,
        project: String = "",
        owner: String = "",
        dueDateText: String = "",
        dueDate: Date? = nil,
        priority: WorkActionPriority = .normal,
        status: WorkActionStatus? = nil,
        evidence: String = "",
        sourceMemoryID: UUID? = nil,
        sourceTitle: String = "",
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        isCompleted: Bool = false,
        reminderIdentifier: String? = nil
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.owner = owner
        self.dueDateText = dueDateText
        self.dueDate = dueDate
        self.priority = priority
        self.status = status ?? (isCompleted ? .completed : .open)
        self.evidence = evidence
        self.sourceMemoryID = sourceMemoryID
        self.sourceTitle = sourceTitle
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.reminderIdentifier = reminderIdentifier
    }

    var dedupeKey: String {
        "\(project)|\(title)"
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, project, owner, dueDateText, dueDate, priority, status, evidence
        case sourceMemoryID, sourceTitle, createdAt, updatedAt, isCompleted, reminderIdentifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        project = try container.decodeIfPresent(String.self, forKey: .project) ?? ""
        owner = try container.decodeIfPresent(String.self, forKey: .owner) ?? ""
        dueDateText = try container.decodeIfPresent(String.self, forKey: .dueDateText) ?? ""
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        priority = try container.decodeIfPresent(WorkActionPriority.self, forKey: .priority) ?? .normal
        let legacyCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        status = try container.decodeIfPresent(WorkActionStatus.self, forKey: .status)
            ?? (legacyCompleted ? .completed : .open)
        evidence = try container.decodeIfPresent(String.self, forKey: .evidence) ?? ""
        sourceMemoryID = try container.decodeIfPresent(UUID.self, forKey: .sourceMemoryID)
        sourceTitle = try container.decodeIfPresent(String.self, forKey: .sourceTitle) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        reminderIdentifier = try container.decodeIfPresent(String.self, forKey: .reminderIdentifier)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(project, forKey: .project)
        try container.encode(owner, forKey: .owner)
        try container.encode(dueDateText, forKey: .dueDateText)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encode(priority, forKey: .priority)
        try container.encode(status, forKey: .status)
        try container.encode(evidence, forKey: .evidence)
        try container.encodeIfPresent(sourceMemoryID, forKey: .sourceMemoryID)
        try container.encode(sourceTitle, forKey: .sourceTitle)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encodeIfPresent(reminderIdentifier, forKey: .reminderIdentifier)
    }
}

struct ActionItemSuggestion: Decodable {
    var title: String
    var project: String?
    var owner: String?
    var dueDateText: String?
    var dueDate: String?
    var priority: String?
    var evidence: String?
    var sourceIndex: Int?
}
