import Foundation

final class ActionItemStore: ObservableObject {
    @Published private(set) var items: [WorkActionItem] = []

    private let database: SQLiteDatabase
    private let legacyFileURL: URL

    init(fileManager: FileManager = .default) {
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("WorkMemory", isDirectory: true)
        ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WorkMemory", isDirectory: true)

        self.legacyFileURL = supportURL.appendingPathComponent("action_items.json")
        self.database = try! SQLiteDatabase(fileManager: fileManager)

        migrateLegacyJSONIfNeeded(fileManager: fileManager)
        items = database.loadActionItems()
    }

    var openItems: [WorkActionItem] {
        items.filter { !$0.isCompleted }
    }

    var completedItems: [WorkActionItem] {
        items.filter(\.isCompleted)
    }

    func addSuggestions(_ suggestions: [ActionItemSuggestion], sourceItems: [MemoryItem]) -> Int {
        var addedCount = 0
        var knownKeys = Set(items.map(\.dedupeKey))

        for suggestion in suggestions {
            let title = suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            let source = sourceItem(for: suggestion.sourceIndex, in: sourceItems)
            let item = WorkActionItem(
                title: title,
                project: suggestion.project?.nilIfBlank ?? inferredProject(from: source),
                owner: suggestion.owner?.nilIfBlank ?? "",
                dueDateText: suggestion.dueDateText?.nilIfBlank ?? "",
                evidence: suggestion.evidence?.nilIfBlank ?? source?.content.clipped(to: 180) ?? "",
                sourceMemoryID: source?.id,
                sourceTitle: source?.title ?? ""
            )

            guard !knownKeys.contains(item.dedupeKey) else { continue }
            items.insert(item, at: 0)
            database.upsertActionItem(item)
            knownKeys.insert(item.dedupeKey)
            addedCount += 1
        }

        return addedCount
    }

    func toggleCompletion(_ item: WorkActionItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isCompleted.toggle()
        database.upsertActionItem(items[index])
    }

    func delete(_ item: WorkActionItem) {
        items.removeAll { $0.id == item.id }
        database.deleteActionItem(id: item.id)
    }

    func updateProject(for item: WorkActionItem, project: String) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].project = project
        database.upsertActionItem(items[index])
    }

    private func sourceItem(for sourceIndex: Int?, in sourceItems: [MemoryItem]) -> MemoryItem? {
        guard let sourceIndex, sourceIndex > 0 else { return nil }
        let index = sourceIndex - 1
        guard sourceItems.indices.contains(index) else { return nil }
        return sourceItems[index]
    }

    private func inferredProject(from source: MemoryItem?) -> String {
        guard let source else { return "" }

        if let context = source.context,
           let windowTitle = context.windowTitle?.nilIfBlank {
            return windowTitle.clipped(to: 36)
        }

        return ""
    }

    private func migrateLegacyJSONIfNeeded(fileManager: FileManager) {
        guard database.loadActionItems().isEmpty,
              fileManager.fileExists(atPath: legacyFileURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: legacyFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let legacyItems = try decoder.decode([WorkActionItem].self, from: data)
            legacyItems.forEach { database.upsertActionItem($0) }
        } catch {
            assertionFailure("Failed to migrate legacy action items: \(error.localizedDescription)")
        }
    }
}
