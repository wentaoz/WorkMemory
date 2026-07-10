import Foundation

struct MemoryItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var content: String
    var category: MemoryCategory
    var actionItems: [String]
    var createdAt: Date
    var updatedAt: Date
    var context: CapturedContext?
    var projectID: UUID?
    var isPinned: Bool
    var sourceReferences: [RecordReference]

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        category: MemoryCategory,
        actionItems: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        context: CapturedContext? = nil,
        projectID: UUID? = nil,
        isPinned: Bool = false,
        sourceReferences: [RecordReference] = []
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.category = category
        self.actionItems = actionItems
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.context = context
        self.projectID = projectID
        self.isPinned = isPinned
        self.sourceReferences = sourceReferences
    }

    var menuTitle: String {
        let cleaned = title.replacingOccurrences(of: "\n", with: " ")
        guard cleaned.count > 28 else { return cleaned }
        return String(cleaned.prefix(28)) + "..."
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, content, category, actionItems, createdAt, updatedAt, context
        case projectID, isPinned, sourceReferences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        category = try container.decodeIfPresent(MemoryCategory.self, forKey: .category) ?? .note
        actionItems = try container.decodeIfPresent([String].self, forKey: .actionItems) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        context = try container.decodeIfPresent(CapturedContext.self, forKey: .context)
        projectID = try container.decodeIfPresent(UUID.self, forKey: .projectID)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        sourceReferences = try container.decodeIfPresent([RecordReference].self, forKey: .sourceReferences) ?? []
    }
}
