import Foundation

@MainActor
final class DailySummaryService: NSObject, ObservableObject {
    @Published private(set) var isSummarizing = false
    @Published private(set) var statusText = "AI 总结未运行"
    @Published private(set) var lastSummaryAt: Date?
    @Published private(set) var progress: Double = 0

    private static let lastAutoSummaryDateKey = "modelAPI.lastAutoSummaryDate"
    private weak var store: MemoryStore?
    private var settings: DeepSeekSettings?
    private let client = DeepSeekClient()
    private var timer: Timer?
    private var summaryTask: Task<Void, Never>?
    private var activeRun: SummaryRun?

    func configure(store: MemoryStore, settings: DeepSeekSettings) {
        self.store = store
        self.settings = settings
        startScheduler()
        runAutomaticCheckNow()
    }

    func summarizeTodayManually() {
        startTask { [weak self] in
            await self?.summarizeToday(isAutomatic: false)
        }
    }

    func summarizeSelectedManually() {
        startTask { [weak self] in
            await self?.summarizeSelected()
        }
    }

    func cancel() {
        summaryTask?.cancel()
        statusText = "AI 总结已取消"
        finishRun(status: .cancelled, errorMessage: "用户取消")
    }

    func runAutomaticCheckNow() {
        guard settings?.autoSummaryEnabled == true, !isSummarizing else { return }
        let now = Date()
        guard Calendar.current.component(.hour, from: now) >= (settings?.autoSummaryHour ?? 18) else { return }
        guard !hasAutoSummarizedToday() else { return }
        startTask { [weak self] in
            await self?.summarizeToday(isAutomatic: true)
        }
    }

    private func startTask(_ operation: @escaping @MainActor () async -> Void) {
        guard summaryTask == nil else { return }
        summaryTask = Task {
            await operation()
            summaryTask = nil
        }
    }

    private func startScheduler() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(
            timeInterval: 60,
            target: self,
            selector: #selector(schedulerTimerFired(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func schedulerTimerFired(_ timer: Timer) {
        runAutomaticCheckNow()
    }

    private func summarizeToday(isAutomatic: Bool) async {
        guard !isSummarizing, let store, let settings else { return }
        let sourceItems = store.sourceItemsForSummary(scope: .today)
        guard !sourceItems.isEmpty else {
            statusText = "今天没有可总结的记录"
            return
        }

        isSummarizing = true
        beginRun(kind: .daily, items: sourceItems, store: store)
        statusText = isAutomatic ? "正在补做今日自动总结..." : "正在整理今日工作会话..."
        defer {
            isSummarizing = false
            if Task.isCancelled { progress = 0 }
        }

        do {
            let summary = try await layeredSummary(
                items: sourceItems,
                settings: settings,
                final: { items, configuration in
                    try await self.client.summarizeDailyRecords(items: items, configuration: configuration)
                }
            )
            try Task.checkCancellation()
            let result = store.addDailySummary(content: summary)
            lastSummaryAt = Date()
            updateProgress(1)
            finishRun(status: .completed, resultMemoryID: result?.id)
            statusText = isAutomatic ? "自动总结已保存" : "今日 AI 总结已保存"
            if isAutomatic { markAutoSummarizedToday() }
            AppLogStore.shared.info(
                "\(isAutomatic ? "自动" : "手动")今日总结已保存，聚合来源 \(sourceItems.count) 条。",
                category: "AI 总结"
            )
        } catch is CancellationError {
            statusText = "AI 总结已取消"
            finishRun(status: .cancelled, errorMessage: "用户取消")
        } catch {
            statusText = error.localizedDescription
            finishRun(status: .failed, errorMessage: error.localizedDescription)
            AppLogStore.shared.error("今日总结失败：\(error.localizedDescription)", category: "AI 总结")
        }
    }

    private func summarizeSelected() async {
        guard !isSummarizing, let store, let settings else { return }
        let sourceItems = store.selectedForSummaryItems
        guard !sourceItems.isEmpty else {
            statusText = "请先勾选要总结的记忆"
            return
        }
        isSummarizing = true
        beginRun(kind: .selected, items: sourceItems, store: store)
        statusText = "正在整理已选 \(sourceItems.count) 条记忆..."
        defer { isSummarizing = false }

        do {
            let summary = try await layeredSummary(
                items: sourceItems,
                settings: settings,
                final: { items, configuration in
                    try await self.client.summarizeSelectedRecords(items: items, configuration: configuration)
                }
            )
            try Task.checkCancellation()
            let result = store.addSelectedSummary(content: summary, sourceCount: sourceItems.count)
            lastSummaryAt = Date()
            updateProgress(1)
            finishRun(status: .completed, resultMemoryID: result?.id)
            statusText = "已选记忆 AI 总结已保存"
        } catch is CancellationError {
            statusText = "AI 总结已取消"
            finishRun(status: .cancelled, errorMessage: "用户取消")
        } catch {
            statusText = error.localizedDescription
            finishRun(status: .failed, errorMessage: error.localizedDescription)
            AppLogStore.shared.error("已选记忆总结失败：\(error.localizedDescription)", category: "AI 总结")
        }
    }

    private func layeredSummary(
        items: [MemoryItem],
        settings: DeepSeekSettings,
        final: ([MemoryItem], DeepSeekClient.Configuration) async throws -> String
    ) async throws -> String {
        let configuration = DeepSeekClient.Configuration(
            apiKey: settings.apiKey,
            baseURL: settings.baseURL,
            model: settings.model
        )
        let batches = stride(from: 0, to: items.count, by: 20).map { start in
            Array(items[start..<min(start + 20, items.count)])
        }
        if batches.count == 1 {
            updateProgress(0.35)
            let result = try await final(items, configuration)
            updateProgress(0.9)
            return result
        }

        var rollups: [MemoryItem] = []
        for (index, batch) in batches.enumerated() {
            try Task.checkCancellation()
            statusText = "正在压缩工作会话 \(index + 1)/\(batches.count)..."
            let content = try await client.summarizeSelectedRecords(items: batch, configuration: configuration)
            rollups.append(MemoryItem(
                title: "工作会话分组 \(index + 1)",
                content: content,
                category: .summary,
                createdAt: batch.first?.createdAt ?? Date()
            ))
            updateProgress(Double(index + 1) / Double(batches.count + 1))
        }
        statusText = "正在生成最终总结..."
        let result = try await final(rollups, configuration)
        updateProgress(0.9)
        return result
    }

    private func beginRun(kind: SummaryRunKind, items: [MemoryItem], store: MemoryStore) {
        let dates = items.map(\.createdAt)
        let now = Date()
        let run = SummaryRun(
            id: UUID(),
            kind: kind,
            status: .running,
            rangeStart: dates.min() ?? now,
            rangeEnd: dates.max() ?? now,
            progress: 0,
            sourceCount: items.count,
            resultMemoryID: nil,
            errorMessage: "",
            createdAt: now,
            updatedAt: now
        )
        activeRun = run
        progress = 0
        store.saveSummaryRun(run)
    }

    private func updateProgress(_ value: Double) {
        progress = min(1, max(0, value))
        guard var run = activeRun else { return }
        run.progress = progress
        run.updatedAt = Date()
        activeRun = run
        store?.saveSummaryRun(run)
    }

    private func finishRun(
        status: SummaryRunStatus,
        resultMemoryID: UUID? = nil,
        errorMessage: String = ""
    ) {
        guard var run = activeRun else { return }
        run.status = status
        run.progress = status == .completed ? 1 : progress
        run.resultMemoryID = resultMemoryID
        run.errorMessage = errorMessage
        run.updatedAt = Date()
        store?.saveSummaryRun(run)
        activeRun = nil
    }

    private func hasAutoSummarizedToday() -> Bool {
        UserDefaults.standard.string(forKey: Self.lastAutoSummaryDateKey) == todayKey()
    }

    private func markAutoSummarizedToday() {
        UserDefaults.standard.set(todayKey(), forKey: Self.lastAutoSummaryDateKey)
    }

    private func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
