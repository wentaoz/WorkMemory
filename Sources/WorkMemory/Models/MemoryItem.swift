import Foundation

struct MemoryItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var content: String
    var category: MemoryCategory
    var actionItems: [String]
    var createdAt: Date
    var context: CapturedContext?

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        category: MemoryCategory,
        actionItems: [String] = [],
        createdAt: Date = Date(),
        context: CapturedContext? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.category = category
        self.actionItems = actionItems
        self.createdAt = createdAt
        self.context = context
    }

    var menuTitle: String {
        let cleaned = title.replacingOccurrences(of: "\n", with: " ")
        guard cleaned.count > 28 else { return cleaned }
        return String(cleaned.prefix(28)) + "..."
    }
}
