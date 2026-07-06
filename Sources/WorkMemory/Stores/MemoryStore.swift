import Foundation

final class MemoryStore: ObservableObject {
    @Published private(set) var items: [MemoryItem] = []
    @Published var searchText = ""
    @Published var selectedItemID: MemoryItem.ID?
    @Published private(set) var selectedForSummaryIDs: Set<MemoryItem.ID> = []
    @Published var composerFocusRequest = UUID()
    @Published var todayViewRequest = UUID()

    private let classifier: MemoryClassifier
    private let database: SQLiteDatabase
    private let legacyFileURL: URL

    init(
        classifier: MemoryClassifier = MemoryClassifier(),
        fileManager: FileManager = .default
    ) {
        self.classifier = classifier

        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("WorkMemory", isDirectory: true)
        ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WorkMemory", isDirectory: true)

        self.legacyFileURL = supportURL.appendingPathComponent("memories.json")
        self.database = try! SQLiteDatabase(fileManager: fileManager)

        migrateLegacyJSONIfNeeded(fileManager: fileManager)
        items = database.loadMemories()
    }

    var recentItems: [MemoryItem] {
        Array(items.prefix(8))
    }

    var selectedItem: MemoryItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    var selectedForSummaryItems: [MemoryItem] {
        items.filter { item in
            selectedForSummaryIDs.contains(item.id)
                && !item.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var selectedForSummaryCount: Int {
        selectedForSummaryItems.count
    }

    var todayItems: [MemoryItem] {
        items.filter { Calendar.current.isDateInToday($0.createdAt) }
    }

    var todaySourceItemsForSummary: [MemoryItem] {
        todayItems.filter { item in
            item.category != .summary && item.context?.source != .aiSummary
        }
    }

    func webPageItems(for range: WebSummaryRange) -> [MemoryItem] {
        items
            .filter { item in
                item.context?.source == .browser
                    && (range.startDate.map { item.createdAt >= $0 } ?? true)
            }
            .prefix(120)
            .map { $0 }
    }

    func queryItems(for scope: MemoryQueryScope) -> [MemoryItem] {
        let scoped: [MemoryItem]
        switch scope {
        case .today:
            scoped = todayItems
        case .lastSevenDays:
            let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            scoped = items.filter { $0.createdAt >= start }
        case .all:
            scoped = items
        }

        return scoped
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(80)
            .map { $0 }
    }

    var openActionItems: [String] {
        todayItems.flatMap(\.actionItems)
    }

    func requestComposerFocus() {
        composerFocusRequest = UUID()
    }

    func requestTodayView() {
        todayViewRequest = UUID()
    }

    func select(item: MemoryItem) {
        selectedItemID = item.id
    }

    func clearSelection() {
        selectedItemID = nil
    }

    func isSelectedForSummary(_ item: MemoryItem) -> Bool {
        selectedForSummaryIDs.contains(item.id)
    }

    func setSelectedForSummary(_ item: MemoryItem, selected: Bool) {
        if selected {
            selectedForSummaryIDs.insert(item.id)
        } else {
            selectedForSummaryIDs.remove(item.id)
        }
    }

    func selectForSummary(items visibleItems: [MemoryItem]) {
        let ids = visibleItems
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(\.id)
        selectedForSummaryIDs.formUnion(ids)
    }

    func clearSummarySelection() {
        selectedForSummaryIDs.removeAll()
    }

    func addMemory(content rawContent: String) {
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        let analysis = classifier.analyze(content)
        let item = MemoryItem(
            title: analysis.title,
            content: content,
            category: analysis.category,
            actionItems: analysis.actionItems
        )

        items.insert(item, at: 0)
        selectedItemID = item.id
        database.upsertMemory(item)
    }

    func addVoiceMemory(content rawContent: String, context: CapturedContext?) {
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        let analysis = classifier.analyze(content)
        let item = MemoryItem(
            title: "全局听写：\(analysis.title)",
            content: content,
            category: analysis.category,
            actionItems: analysis.actionItems,
            context: context ?? CapturedContext(source: .voice)
        )

        items.insert(item, at: 0)
        selectedItemID = item.id
        database.upsertMemory(item)
    }

    func addDailySummary(content rawContent: String, date: Date = Date()) {
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        let item = MemoryItem(
            title: "AI 今日总结：\(DateFormatting.mediumDate.string(from: date))",
            content: content,
            category: .summary,
            actionItems: [],
            createdAt: Date(),
            context: CapturedContext(source: .aiSummary)
        )

        items.insert(item, at: 0)
        selectedItemID = item.id
        database.upsertMemory(item)
    }

    func addWebSummary(content rawContent: String, range: WebSummaryRange, sourceCount: Int) {
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        let item = MemoryItem(
            title: "AI 网页摘要：\(range.label)",
            content: content,
            category: .summary,
            actionItems: [],
            createdAt: Date(),
            context: CapturedContext(
                source: .aiSummary,
                appName: "Web",
                windowTitle: "\(range.label) · \(sourceCount) 条网页记录"
            )
        )

        items.insert(item, at: 0)
        selectedItemID = item.id
        database.upsertMemory(item)
    }

    func addSelectedSummary(content rawContent: String, sourceCount: Int) {
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        let item = MemoryItem(
            title: "AI 精选总结：\(sourceCount) 条记忆",
            content: content,
            category: .summary,
            actionItems: [],
            createdAt: Date(),
            context: CapturedContext(
                source: .aiSummary,
                appName: "Selected Memories",
                windowTitle: "\(sourceCount) 条手动选择的记忆"
            )
        )

        items.insert(item, at: 0)
        selectedItemID = item.id
        selectedForSummaryIDs.removeAll()
        database.upsertMemory(item)
    }

    func addDocumentSummary(
        content rawContent: String,
        fileName: String,
        filePath: String,
        modifiedAt: Date
    ) {
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        let item = MemoryItem(
            title: "文档摘要：\(fileName)",
            content: content,
            category: .document,
            actionItems: classifier.analyze(content).actionItems,
            createdAt: Date(),
            context: CapturedContext(
                source: .localDocument,
                appName: "Finder",
                windowTitle: fileName,
                pageTitle: DateFormatting.dateTime.string(from: modifiedAt),
                url: filePath
            )
        )

        items.insert(item, at: 0)
        selectedItemID = item.id
        database.upsertMemory(item)
    }

    func addCapturedMemory(_ snapshot: PassiveCaptureSnapshot) {
        let content = snapshot.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        let item = MemoryItem(
            title: title(for: snapshot, content: content),
            content: content,
            category: category(for: snapshot, content: content),
            actionItems: snapshot.source == .typing ? classifier.analyze(content).actionItems : [],
            createdAt: snapshot.createdAt,
            context: snapshot.context
        )

        items.insert(item, at: 0)
        database.upsertMemory(item)
    }

    func updateCategory(for item: MemoryItem, to category: MemoryCategory) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].category = category
        database.upsertMemory(items[index])
    }

    func delete(_ item: MemoryItem) {
        items.removeAll { $0.id == item.id }
        selectedForSummaryIDs.remove(item.id)
        if selectedItemID == item.id {
            selectedItemID = items.first?.id
        }
        database.deleteMemory(id: item.id)
    }

    func items(for selection: SidebarSelection) -> [MemoryItem] {
        let scoped: [MemoryItem]
        switch selection {
        case .today:
            scoped = todayItems
        case .all:
            scoped = items
        case .summaries, .askMemory, .actions, .logs, .settings:
            scoped = []
        case .category(let category):
            scoped = items.filter { item in
                if category == .web {
                    return item.category == .web || item.context?.source == .browser
                }

                return item.category == category
            }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return scoped }

        let databaseMatchedIDs = database.searchMemoryIDs(query: query)
        if !databaseMatchedIDs.isEmpty {
            return scoped.filter { databaseMatchedIDs.contains($0.id) }
        }

        return scoped.filter { item in
            item.title.localizedCaseInsensitiveContains(query)
            || item.content.localizedCaseInsensitiveContains(query)
            || item.category.label.localizedCaseInsensitiveContains(query)
            || item.context?.summary.localizedCaseInsensitiveContains(query) == true
            || item.actionItems.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    func count(for category: MemoryCategory) -> Int {
        if category == .web {
            return items.filter { $0.category == .web || $0.context?.source == .browser }.count
        }

        return items.filter { $0.category == category }.count
    }

    private func migrateLegacyJSONIfNeeded(fileManager: FileManager) {
        guard database.loadMemories().isEmpty,
              fileManager.fileExists(atPath: legacyFileURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: legacyFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let legacyItems = try decoder.decode([MemoryItem].self, from: data)
            legacyItems.forEach { database.upsertMemory($0) }
        } catch {
            assertionFailure("Failed to migrate legacy memories: \(error.localizedDescription)")
        }
    }

    private func title(for snapshot: PassiveCaptureSnapshot, content: String) -> String {
        switch snapshot.source {
        case .typing:
            let target = snapshot.windowTitle ?? snapshot.appName ?? "当前输入"
            return "写作片段：\(target)"
        case .browser:
            let target = snapshot.pageTitle ?? snapshot.windowTitle ?? snapshot.url ?? "网页"
            return "正在浏览：\(target)"
        case .activeWindow:
            let target = snapshot.windowTitle ?? snapshot.appName ?? "窗口"
            return "正在查看：\(target)"
        case .ocr:
            let target = snapshot.pageTitle ?? snapshot.windowTitle ?? snapshot.appName ?? "当前窗口"
            return "OCR 识别：\(target)"
        case .aiSummary:
            return "AI 今日总结"
        case .localDocument:
            return "本地文档摘要"
        case .manual, .voice:
            let analysis = classifier.analyze(content)
            return analysis.title
        }
    }

    private func category(for snapshot: PassiveCaptureSnapshot, content: String) -> MemoryCategory {
        switch snapshot.source {
        case .browser:
            return .web
        case .localDocument:
            return .document
        case .aiSummary:
            return .summary
        case .manual, .voice:
            return classifier.analyze(content).category
        default:
            return .context
        }
    }
}
