import Foundation

@MainActor
final class WebSummaryService: ObservableObject {
    @Published var range: WebSummaryRange = .today
    @Published private(set) var isSummarizing = false
    @Published private(set) var statusText = "网页摘要未运行"
    @Published private(set) var lastSummaryAt: Date?

    private weak var store: MemoryStore?
    private var settings: DeepSeekSettings?
    private let client = DeepSeekClient()

    func configure(store: MemoryStore, settings: DeepSeekSettings) {
        self.store = store
        self.settings = settings
    }

    func summarize() {
        Task {
            await summarizeSelectedRange()
        }
    }

    private func summarizeSelectedRange() async {
        guard !isSummarizing else { return }
        guard let store, let settings else { return }

        let sourceItems = store.webPageItems(for: range)
        guard !sourceItems.isEmpty else {
            statusText = "\(range.label)没有可总结的网页记录"
            return
        }

        isSummarizing = true
        statusText = "正在总结\(range.label)网页..."

        do {
            let summary = try await client.summarizeWebPages(
                items: sourceItems,
                range: range,
                configuration: DeepSeekClient.Configuration(
                    apiKey: settings.apiKey,
                    baseURL: settings.baseURL,
                    model: settings.model
                )
            )

            store.addWebSummary(content: summary, range: range, sourceCount: sourceItems.count)
            lastSummaryAt = Date()
            statusText = "\(range.label)网页摘要已保存"
            AppLogStore.shared.info("\(range.label)网页摘要已保存，来源网页 \(sourceItems.count) 条。", category: "网页摘要")
        } catch {
            statusText = error.localizedDescription
            AppLogStore.shared.error("\(range.label)网页摘要失败：\(error.localizedDescription)", category: "网页摘要")
        }

        isSummarizing = false
    }
}
