import Foundation

@MainActor
final class ActionItemExtractionService: ObservableObject {
    @Published private(set) var isExtracting = false
    @Published private(set) var statusText = "行动项未抽取"
    @Published private(set) var lastExtractedAt: Date?

    private weak var memoryStore: MemoryStore?
    private weak var actionStore: ActionItemStore?
    private var settings: DeepSeekSettings?
    private let client = DeepSeekClient()

    func configure(
        memoryStore: MemoryStore,
        actionStore: ActionItemStore,
        settings: DeepSeekSettings
    ) {
        self.memoryStore = memoryStore
        self.actionStore = actionStore
        self.settings = settings
    }

    func extractToday() {
        Task {
            await extract(scope: .today)
        }
    }

    func extractLastSevenDays() {
        Task {
            await extract(scope: .lastSevenDays)
        }
    }

    private func extract(scope: MemoryQueryScope) async {
        guard !isExtracting else { return }
        guard let memoryStore, let actionStore, let settings else { return }

        let sourceItems = memoryStore.queryItems(for: scope)
            .filter { $0.category != .summary && $0.context?.source != .aiSummary }

        guard !sourceItems.isEmpty else {
            statusText = "\(scope.label)没有可抽取的记录"
            return
        }

        isExtracting = true
        statusText = "正在从\(scope.label)记录抽取行动项..."

        do {
            let suggestions = try await client.extractActionItems(
                items: sourceItems,
                configuration: DeepSeekClient.Configuration(
                    apiKey: settings.apiKey,
                    baseURL: settings.baseURL,
                    model: settings.model
                )
            )

            let addedCount = actionStore.addSuggestions(suggestions, sourceItems: sourceItems)
            lastExtractedAt = Date()
            statusText = addedCount > 0 ? "已新增 \(addedCount) 个行动项" : "没有新增行动项"
            AppLogStore.shared.info(
                "\(scope.label)行动项抽取完成，来源记录 \(sourceItems.count) 条，新增 \(addedCount) 个。",
                category: "行动项"
            )
        } catch {
            statusText = error.localizedDescription
            AppLogStore.shared.error("\(scope.label)行动项抽取失败：\(error.localizedDescription)", category: "行动项")
        }

        isExtracting = false
    }
}
