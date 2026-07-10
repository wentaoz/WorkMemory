import Foundation

final class ActionItemStore: ObservableObject {
    @Published private(set) var items: [WorkActionItem] = []

    private let database: SQLiteDatabase
    private let legacyFileURL: URL

    init(fileManager: FileManager = .default) {
        let supportURL = WorkMemoryDataLocation.supportURL(fileManager: fileManager)

        self.legacyFileURL = supportURL.appendingPathComponent("action_items.json")
        do {
            self.database = try SQLiteDatabase(fileManager: fileManager)
        } catch {
            fatalError("Unable to open WorkMemory action database: \(error.localizedDescription)")
        }

        migrateLegacyJSONIfNeeded(fileManager: fileManager)
        items = database.loadActionItems()
        seedDemoDataIfRequested()
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
                dueDate: parsedDate(suggestion.dueDate),
                priority: suggestion.priority.flatMap(WorkActionPriority.init(rawValue:)) ?? .normal,
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
        items[index].updatedAt = Date()
        database.upsertActionItem(items[index])
    }

    func add(_ item: WorkActionItem) {
        items.insert(item, at: 0)
        database.upsertActionItem(item)
    }

    func update(_ item: WorkActionItem) {
        var updated = item
        updated.updatedAt = Date()
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = updated
        } else {
            items.insert(updated, at: 0)
        }
        database.upsertActionItem(updated)
    }

    func deferAction(_ item: WorkActionItem) {
        var updated = item
        updated.status = .deferred
        update(updated)
    }

    func setReminderIdentifier(_ identifier: String, for item: WorkActionItem) {
        var updated = item
        updated.reminderIdentifier = identifier
        update(updated)
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

    private func parsedDate(_ rawValue: String?) -> Date? {
        guard let value = rawValue?.nilIfBlank else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
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

    private func seedDemoDataIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["WORKMEMORY_DEMO_SEED"] == "1",
              items.isEmpty else { return }
        let samples = [
            WorkActionItem(
                title: "完成 1.1.0 发布候选版检查",
                project: "Northstar 发布",
                owner: "William",
                dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()),
                priority: .urgent,
                evidence: "发布范围已确认"
            ),
            WorkActionItem(
                title: "整理 Ask Memory 引用示例",
                project: "Northstar 发布",
                priority: .high,
                evidence: "客户访谈要求回答可追溯"
            )
        ]
        samples.forEach(database.upsertActionItem)
        items = database.loadActionItems()
        #endif
    }
}
