import Foundation
import CryptoKit

final class MemoryStore: ObservableObject {
    @Published private(set) var items: [MemoryItem] = []
    @Published private(set) var activities: [ActivitySession] = []
    @Published private(set) var projects: [MemoryProject] = []
    @Published private(set) var summaryHistory: [MemoryItem] = []
    @Published private(set) var summaryRuns: [SummaryRun] = []
    @Published private(set) var totalMemoryCount = 0
    @Published private(set) var totalActivityCount = 0
    @Published private(set) var archivedActivityCount = 0
    @Published var searchText = ""
    @Published var selectedItemID: MemoryItem.ID?
    @Published var selectedActivityID: ActivitySession.ID?
    @Published private(set) var selectedForSummaryIDs: Set<MemoryItem.ID> = []
    @Published var composerFocusRequest = UUID()
    @Published var todayViewRequest = UUID()

    private let classifier: MemoryClassifier
    let database: SQLiteDatabase
    private let legacyFileURL: URL
    private let pageSize = 100
    private lazy var hybridSearch = HybridMemorySearch(database: database)

    init(
        classifier: MemoryClassifier = MemoryClassifier(),
        fileManager: FileManager = .default,
        supportURL explicitSupportURL: URL? = nil
    ) {
        self.classifier = classifier

        let supportURL = explicitSupportURL ?? WorkMemoryDataLocation.supportURL(fileManager: fileManager)

        self.legacyFileURL = supportURL.appendingPathComponent("memories.json")
        do {
            self.database = try SQLiteDatabase(fileManager: fileManager, supportURL: supportURL)
        } catch {
            fatalError("Unable to open WorkMemory database: \(error.localizedDescription)")
        }

        migrateLegacyJSONIfNeeded(fileManager: fileManager)
        database.archiveActivities(
            endingBefore: Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        )
        items = database.loadMemories(limit: pageSize)
        activities = database.loadRecentActivities(limit: 200)
        projects = database.loadProjects()
        summaryHistory = database.loadMemories(category: .summary)
        database.markInterruptedSummaryRunsFailed()
        summaryRuns = database.loadSummaryRuns()
        refreshCounts()
        seedDemoDataIfRequested()
    }

    var hasExistingData: Bool {
        totalMemoryCount + totalActivityCount + archivedActivityCount > 0
    }

    var databaseSize: Int64 { database.databaseFileSize }
    var databaseSchemaVersion: Int { database.schemaVersion }
    var databasePath: String { database.databaseURL.path }

    var recentItems: [MemoryItem] {
        Array(items.prefix(8))
    }

    var selectedItem: MemoryItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    var selectedActivity: ActivitySession? {
        guard let selectedActivityID else { return nil }
        return activities.first(where: { $0.id == selectedActivityID }) ?? database.loadActivity(id: selectedActivityID)
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

    var todayActivities: [ActivitySession] {
        activities.filter { Calendar.current.isDateInToday($0.endedAt) }
    }

    var todaySourceItemsForSummary: [MemoryItem] {
        sourceItemsForSummary(scope: .today)
    }

    func sourceItemsForSummary(scope: MemoryQueryScope) -> [MemoryItem] {
        let calendar = Calendar.current
        let memoryItems = items.filter { item in
            guard item.category != .summary, item.context?.source != .aiSummary else { return false }
            switch scope {
            case .today:
                return calendar.isDateInToday(item.createdAt)
            case .lastSevenDays:
                let start = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                return item.createdAt >= start
            case .all:
                return true
            }
        }
        let activityItems = activities.filter { activity in
            switch scope {
            case .today:
                return calendar.isDateInToday(activity.endedAt)
            case .lastSevenDays:
                let start = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                return activity.endedAt >= start
            case .all:
                return true
            }
        }.map { activity in
            MemoryItem(
                id: activity.id,
                title: activity.displayTitle,
                content: activity.content,
                category: activity.source == .browser ? .web : .context,
                createdAt: activity.endedAt,
                context: activity.context,
                projectID: activity.projectID,
                sourceReferences: [RecordReference(kind: .activity, id: activity.id)]
            )
        }
        return (memoryItems + activityItems)
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(300)
            .map { $0 }
    }

    func webPageItems(for range: WebSummaryRange) -> [MemoryItem] {
        let memoryItems = items
            .filter { item in
                item.context?.source == .browser
                    && (range.startDate.map { item.createdAt >= $0 } ?? true)
            }
        let activityItems = activities
            .filter { activity in
                activity.source == .browser
                    && (range.startDate.map { activity.endedAt >= $0 } ?? true)
            }
            .map { activity in
                MemoryItem(
                    id: activity.id,
                    title: activity.displayTitle,
                    content: activity.content,
                    category: .web,
                    createdAt: activity.endedAt,
                    context: activity.context,
                    projectID: activity.projectID,
                    sourceReferences: [RecordReference(kind: .activity, id: activity.id)]
                )
            }
        return (memoryItems + activityItems)
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(120)
            .map { $0 }
    }

    func queryItems(for scope: MemoryQueryScope) -> [MemoryItem] {
        sourceItemsForSummary(scope: scope)
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(80)
            .map { $0 }
    }

    func rankedResults(
        for question: String,
        scope: MemoryQueryScope,
        projectID: UUID? = nil,
        limit: Int = 24
    ) -> [RankedMemoryResult] {
        hybridSearch.search(question: question, scope: scope, projectID: projectID, limit: limit)
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
        if !items.contains(where: { $0.id == item.id }) {
            items.insert(item, at: 0)
        }
        selectedItemID = item.id
    }

    func clearSelection() {
        selectedItemID = nil
        selectedActivityID = nil
    }

    func select(reference: RecordReference) {
        switch reference.kind {
        case .memory:
            if let item = items.first(where: { $0.id == reference.id }) ?? database.loadMemory(id: reference.id) {
                if !items.contains(where: { $0.id == item.id }) { items.insert(item, at: 0) }
                selectedActivityID = nil
                selectedItemID = item.id
            }
        case .chunk:
            if let memoryID = database.parentMemoryID(forChunkID: reference.id),
               let item = items.first(where: { $0.id == memoryID }) ?? database.loadMemory(id: memoryID) {
                if !items.contains(where: { $0.id == item.id }) { items.insert(item, at: 0) }
                selectedActivityID = nil
                selectedItemID = item.id
            }
        case .activity:
            selectedItemID = nil
            selectedActivityID = reference.id
        case .action:
            break
        }
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
        refreshCounts()
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
        refreshCounts()
    }

    @discardableResult
    func addDailySummary(content rawContent: String, date: Date = Date()) -> MemoryItem? {
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }

        let item = MemoryItem(
            title: "AI 今日总结：\(DateFormatting.mediumDate.string(from: date))",
            content: content,
            category: .summary,
            actionItems: [],
            createdAt: Date(),
            context: CapturedContext(source: .aiSummary)
        )

        items.insert(item, at: 0)
        summaryHistory.insert(item, at: 0)
        selectedItemID = item.id
        database.upsertMemory(item)
        refreshCounts()
        return item
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
        summaryHistory.insert(item, at: 0)
        selectedItemID = item.id
        database.upsertMemory(item)
        refreshCounts()
    }

    @discardableResult
    func addSelectedSummary(content rawContent: String, sourceCount: Int) -> MemoryItem? {
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }

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
        summaryHistory.insert(item, at: 0)
        selectedItemID = item.id
        selectedForSummaryIDs.removeAll()
        database.upsertMemory(item)
        refreshCounts()
        return item
    }

    @discardableResult
    func addDocumentSummary(
        content rawContent: String,
        fileName: String,
        filePath: String,
        modifiedAt: Date
    ) -> MemoryItem? {
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }

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
        refreshCounts()
        return item
    }

    func storeDocumentChunks(_ chunks: [MemoryChunk], for memoryID: UUID) {
        database.replaceChunks(memoryID: memoryID, chunks: chunks)
    }

    func addCapturedMemory(_ snapshot: PassiveCaptureSnapshot) {
        let content = snapshot.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        let contextKey = activityContextKey(for: snapshot)
        let digest = contentDigest(content)
        let mergeCutoff = snapshot.createdAt.addingTimeInterval(-10 * 60)

        if var existing = database.mergeableActivity(contextKey: contextKey, after: mergeCutoff) {
            existing.endedAt = max(existing.endedAt, snapshot.createdAt)
            existing.eventCount += 1
            if existing.contentDigest != digest {
                let appended = existing.content + "\n\n---\n\n" + content
                existing.content = String(appended.suffix(12_000))
                existing.contentDigest = digest
            }
            database.upsertActivity(existing)
            replaceRecentActivity(existing)
            refreshCounts()
            return
        }

        guard !database.activityExists(digest: digest, since: snapshot.createdAt.addingTimeInterval(-120)) else {
            return
        }
        let activity = ActivitySession(
            source: snapshot.source,
            contextKey: contextKey,
            content: content.clipped(to: 12_000),
            context: snapshot.context,
            startedAt: snapshot.createdAt,
            endedAt: snapshot.createdAt,
            contentDigest: digest
        )
        database.upsertActivity(activity)
        activities.insert(activity, at: 0)
        if activities.count > 200 { activities.removeLast(activities.count - 200) }
        refreshCounts()
    }

    func promoteActivity(_ activity: ActivitySession) {
        guard activity.promotedMemoryID == nil else { return }
        let analysis = classifier.analyze(activity.content)
        let memory = MemoryItem(
            title: analysis.title,
            content: activity.content,
            category: analysis.category,
            actionItems: analysis.actionItems,
            createdAt: activity.endedAt,
            context: activity.context,
            projectID: activity.projectID,
            sourceReferences: [RecordReference(kind: .activity, id: activity.id)]
        )
        database.upsertMemory(memory)
        var promoted = activity
        promoted.promotedMemoryID = memory.id
        promoted.isArchived = true
        database.upsertActivity(promoted)
        items.insert(memory, at: 0)
        activities.removeAll { $0.id == activity.id }
        refreshCounts()
    }

    func loadMoreMemories() {
        guard items.count < totalMemoryCount else { return }
        let next = database.loadMemories(limit: pageSize, offset: items.count)
        let known = Set(items.map(\.id))
        items.append(contentsOf: next.filter { !known.contains($0.id) })
    }

    func addProject(named rawName: String) -> MemoryProject? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if let existing = projects.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let project = MemoryProject(name: name)
        database.upsertProject(project)
        projects.insert(project, at: 0)
        return project
    }

    func updateMemory(_ item: MemoryItem, projectID: UUID?, isPinned: Bool) {
        var updated = items.first(where: { $0.id == item.id }) ?? item
        updated.projectID = projectID
        updated.isPinned = isPinned
        updated.updatedAt = Date()
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = updated
        }
        if let index = summaryHistory.firstIndex(where: { $0.id == item.id }) {
            summaryHistory[index] = updated
        }
        database.upsertMemory(updated)
    }

    func assignActivity(_ activity: ActivitySession, to projectID: UUID?) {
        var updated = activity
        updated.projectID = projectID
        database.upsertActivity(updated)
        replaceRecentActivity(updated)
    }

    func projectName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return projects.first(where: { $0.id == id })?.name
    }

    func updateCategory(for item: MemoryItem, to category: MemoryCategory) {
        var updated = items.first(where: { $0.id == item.id }) ?? item
        updated.category = category
        updated.updatedAt = Date()
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = updated
        }
        database.upsertMemory(updated)
        summaryHistory = database.loadMemories(category: .summary)
    }

    func delete(_ item: MemoryItem) {
        items.removeAll { $0.id == item.id }
        selectedForSummaryIDs.remove(item.id)
        if selectedItemID == item.id {
            selectedItemID = items.first?.id
        }
        database.deleteMemory(id: item.id)
        summaryHistory.removeAll { $0.id == item.id }
        refreshCounts()
    }

    func items(for selection: SidebarSelection) -> [MemoryItem] {
        let scoped: [MemoryItem]
        switch selection {
        case .today:
            scoped = todayItems
        case .all:
            scoped = items
        case .summaries, .askMemory, .actions, .projects, .logs, .settings:
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
        database.memoryCount(category: category)
    }

    func saveSummaryRun(_ run: SummaryRun) {
        database.upsertSummaryRun(run)
        if let index = summaryRuns.firstIndex(where: { $0.id == run.id }) {
            summaryRuns[index] = run
        } else {
            summaryRuns.insert(run, at: 0)
        }
        if summaryRuns.count > 30 { summaryRuns.removeLast(summaryRuns.count - 30) }
    }

    private func refreshCounts() {
        totalMemoryCount = database.memoryCount()
        totalActivityCount = database.activityCount()
        archivedActivityCount = max(0, database.activityCount(includeArchived: true) - totalActivityCount)
    }

    private func seedDemoDataIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["WORKMEMORY_DEMO_SEED"] == "1",
              !hasExistingData else { return }

        let project = MemoryProject(name: "Northstar 发布")
        database.upsertProject(project)
        projects = [project]

        let samples = [
            MemoryItem(
                title: "确认 1.1.0 发布范围",
                content: "决定本周发布 1.1.0，重点完成工作会话聚合、Ask Memory 引用和行动项闭环。",
                category: .decision,
                actionItems: ["完成发布候选版检查"],
                createdAt: Date().addingTimeInterval(-3_600),
                projectID: project.id,
                isPinned: true
            ),
            MemoryItem(
                title: "客户访谈要点",
                content: "用户希望快速回看当天工作脉络，并能从原始活动一键提炼为长期记忆。",
                category: .meeting,
                createdAt: Date().addingTimeInterval(-7_200),
                projectID: project.id
            ),
            MemoryItem(
                title: "检索质量观察",
                content: "项目名称、决策词和文档页码应在回答中作为可点击证据返回。",
                category: .idea,
                createdAt: Date().addingTimeInterval(-10_800),
                projectID: project.id
            ),
            MemoryItem(
                title: "AI 今日总结：演示数据",
                content: "# 今日摘要\n\n- 完成发布范围确认。\n- 聚焦记忆到行动的工作流。\n- 下一步是完成回归并发布安装包。",
                category: .summary,
                createdAt: Date().addingTimeInterval(-900),
                context: CapturedContext(source: .aiSummary),
                projectID: project.id
            )
        ]
        samples.forEach(database.upsertMemory)

        let now = Date()
        addCapturedMemory(PassiveCaptureSnapshot(
            source: .browser,
            content: "页面：WorkMemory 1.1 release checklist\nURL：https://example.test/release\n\n核对版本、安装包和更新说明。",
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            windowTitle: "Release checklist",
            pageTitle: "WorkMemory 1.1 release checklist",
            url: "https://example.test/release",
            createdAt: now.addingTimeInterval(-1_800)
        ))
        addCapturedMemory(PassiveCaptureSnapshot(
            source: .activeWindow,
            content: "正在整理 Ask Memory 引用跳转和项目筛选。",
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            windowTitle: "WorkMemory - AskMemoryView.swift",
            createdAt: now.addingTimeInterval(-1_200)
        ))

        items = database.loadMemories(limit: pageSize)
        activities = database.loadRecentActivities(limit: 200)
        summaryHistory = database.loadMemories(category: .summary)
        refreshCounts()
        #endif
    }

    private func replaceRecentActivity(_ activity: ActivitySession) {
        if let index = activities.firstIndex(where: { $0.id == activity.id }) {
            activities[index] = activity
            activities.sort { $0.endedAt > $1.endedAt }
        } else {
            activities.insert(activity, at: 0)
        }
    }

    private func activityContextKey(for snapshot: PassiveCaptureSnapshot) -> String {
        [
            snapshot.source.rawValue,
            snapshot.bundleIdentifier ?? snapshot.appName ?? "",
            snapshot.url ?? snapshot.windowTitle ?? snapshot.pageTitle ?? ""
        ].joined(separator: "|").lowercased()
    }

    private func contentDigest(_ content: String) -> String {
        let normalized = content.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
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
