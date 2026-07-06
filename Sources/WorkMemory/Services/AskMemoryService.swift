import Foundation

@MainActor
final class AskMemoryService: ObservableObject {
    @Published var question = ""
    @Published var scope: MemoryQueryScope = .today
    @Published private(set) var answer = ""
    @Published private(set) var statusText = "Ask Memory 未运行"
    @Published private(set) var isAsking = false
    @Published private(set) var referencedItems: [MemoryItem] = []

    private weak var memoryStore: MemoryStore?
    private var settings: DeepSeekSettings?
    private let client = DeepSeekClient()

    func configure(memoryStore: MemoryStore, settings: DeepSeekSettings) {
        self.memoryStore = memoryStore
        self.settings = settings
    }

    func ask() {
        Task {
            await runAsk()
        }
    }

    private func runAsk() async {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else {
            statusText = "请输入问题"
            return
        }

        guard !isAsking else { return }
        guard let memoryStore, let settings else { return }

        let sourceItems = memoryStore.queryItems(for: scope)
        guard !sourceItems.isEmpty else {
            statusText = "\(scope.label)没有可问答的记录"
            return
        }

        isAsking = true
        answer = ""
        referencedItems = sourceItems
        statusText = "正在查询\(scope.label)记忆..."

        do {
            answer = try await client.askMemory(
                question: trimmedQuestion,
                items: sourceItems,
                scope: scope,
                configuration: DeepSeekClient.Configuration(
                    apiKey: settings.apiKey,
                    baseURL: settings.baseURL,
                    model: settings.model
                )
            )
            statusText = "Ask Memory 已完成"
            AppLogStore.shared.info("\(scope.label)问答已完成，引用记录 \(sourceItems.count) 条。", category: "Ask Memory")
        } catch {
            statusText = error.localizedDescription
            AppLogStore.shared.error("\(scope.label)问答失败：\(error.localizedDescription)", category: "Ask Memory")
        }

        isAsking = false
    }
}
