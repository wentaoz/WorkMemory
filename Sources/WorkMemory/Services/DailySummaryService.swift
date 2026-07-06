import Foundation

@MainActor
final class DailySummaryService: ObservableObject {
    @Published private(set) var isSummarizing = false
    @Published private(set) var statusText = "AI 总结未运行"
    @Published private(set) var lastSummaryAt: Date?

    private static let lastAutoSummaryDateKey = "deepseek.lastAutoSummaryDate"

    private weak var store: MemoryStore?
    private var settings: DeepSeekSettings?
    private let client = DeepSeekClient()
    private var timer: Timer?

    func configure(store: MemoryStore, settings: DeepSeekSettings) {
        self.store = store
        self.settings = settings
        startScheduler()
    }

    func summarizeTodayManually() {
        Task {
            await summarizeToday(isAutomatic: false)
        }
    }

    func summarizeSelectedManually() {
        Task {
            await summarizeSelected()
        }
    }

    func runAutomaticCheckNow() {
        guard settings?.autoSummaryEnabled == true else { return }

        let now = Date()
        guard Calendar.current.component(.hour, from: now) == 18 else { return }
        guard !hasAutoSummarizedToday() else { return }

        Task {
            await summarizeToday(isAutomatic: true)
        }
    }

    private func startScheduler() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.runAutomaticCheckNow()
            }
        }
    }

    private func summarizeToday(isAutomatic: Bool) async {
        guard !isSummarizing else { return }
        guard let store, let settings else { return }

        let sourceItems = store.todaySourceItemsForSummary
        guard !sourceItems.isEmpty else {
            statusText = "今天没有可总结的记录"
            return
        }

        isSummarizing = true
        statusText = isAutomatic ? "正在自动总结今日记录..." : "正在总结今日记录..."

        do {
            let summary = try await client.summarizeDailyRecords(
                items: sourceItems,
                configuration: DeepSeekClient.Configuration(
                    apiKey: settings.apiKey,
                    baseURL: settings.baseURL,
                    model: settings.model
                )
            )

            store.addDailySummary(content: summary)
            lastSummaryAt = Date()
            statusText = isAutomatic ? "18:00 自动总结已保存" : "今日 AI 总结已保存"
            AppLogStore.shared.info(
                "\(isAutomatic ? "自动" : "手动")今日总结已保存，来源记录 \(sourceItems.count) 条。",
                category: "AI 总结"
            )

            if isAutomatic {
                markAutoSummarizedToday()
            }
        } catch {
            statusText = error.localizedDescription
            AppLogStore.shared.error("今日总结失败：\(error.localizedDescription)", category: "AI 总结")
        }

        isSummarizing = false
    }

    private func summarizeSelected() async {
        guard !isSummarizing else { return }
        guard let store, let settings else { return }

        let sourceItems = store.selectedForSummaryItems
        guard !sourceItems.isEmpty else {
            statusText = "请先勾选要总结的记忆"
            return
        }

        isSummarizing = true
        statusText = "正在总结已选 \(sourceItems.count) 条记忆..."

        do {
            let summary = try await client.summarizeSelectedRecords(
                items: sourceItems,
                configuration: DeepSeekClient.Configuration(
                    apiKey: settings.apiKey,
                    baseURL: settings.baseURL,
                    model: settings.model
                )
            )

            store.addSelectedSummary(content: summary, sourceCount: sourceItems.count)
            lastSummaryAt = Date()
            statusText = "已选记忆 AI 总结已保存"
            AppLogStore.shared.info("已选记忆总结已保存，来源记录 \(sourceItems.count) 条。", category: "AI 总结")
        } catch {
            statusText = error.localizedDescription
            AppLogStore.shared.error("已选记忆总结失败：\(error.localizedDescription)", category: "AI 总结")
        }

        isSummarizing = false
    }

    private func hasAutoSummarizedToday() -> Bool {
        let stored = UserDefaults.standard.string(forKey: Self.lastAutoSummaryDateKey)
        return stored == todayKey()
    }

    private func markAutoSummarizedToday() {
        UserDefaults.standard.set(todayKey(), forKey: Self.lastAutoSummaryDateKey)
    }

    private func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
