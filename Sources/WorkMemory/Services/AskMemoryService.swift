import Foundation

@MainActor
final class AskMemoryService: ObservableObject {
    @Published var question = ""
    @Published var scope: MemoryQueryScope = .today
    @Published var selectedProjectID: UUID?
    @Published private(set) var answer = ""
    @Published private(set) var statusText = "Ask Memory 未运行"
    @Published private(set) var isAsking = false
    @Published private(set) var referencedItems: [MemoryItem] = []
    @Published private(set) var turns: [AskMemoryTurn] = []

    private weak var memoryStore: MemoryStore?
    private var settings: DeepSeekSettings?
    private let client = DeepSeekClient()

    func configure(memoryStore: MemoryStore, settings: DeepSeekSettings) {
        self.memoryStore = memoryStore
        self.settings = settings
    }

    func ask() {
        Task { await runAsk() }
    }

    func clearConversation() {
        turns.removeAll()
        answer = ""
        referencedItems = []
        statusText = "Ask Memory 未运行"
    }

    private func runAsk() async {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else {
            statusText = "请输入问题"
            return
        }
        guard !isAsking, let memoryStore, let settings else { return }

        statusText = "正在本地检索\(scope.label)记忆..."
        let ranked = memoryStore.rankedResults(
            for: trimmedQuestion,
            scope: scope,
            projectID: selectedProjectID
        )
        guard !ranked.isEmpty else {
            statusText = "\(scope.label)没有相关记录"
            return
        }

        let sourceItems = ranked.map { result in
            MemoryItem(
                id: result.record.reference.id,
                title: result.record.title,
                content: result.record.content,
                category: result.record.reference.kind == .activity ? .context : .note,
                createdAt: result.record.createdAt,
                projectID: result.record.projectID
            )
        }
        let citations = ranked.enumerated().map { index, result in
            MemoryCitation(
                marker: "[\(index + 1)]",
                title: result.record.title,
                excerpt: result.record.content.clipped(to: 180),
                locator: result.record.locator,
                reference: result.record.reference
            )
        }

        isAsking = true
        answer = ""
        referencedItems = sourceItems
        statusText = "已找到 \(sourceItems.count) 条证据，正在生成回答..."
        defer { isAsking = false }

        do {
            answer = try await client.askMemory(
                question: trimmedQuestion,
                items: sourceItems,
                scope: scope,
                conversationContext: conversationContext,
                configuration: DeepSeekClient.Configuration(
                    apiKey: settings.apiKey,
                    baseURL: settings.baseURL,
                    model: settings.model
                )
            )
            turns.append(AskMemoryTurn(question: trimmedQuestion, answer: answer, citations: citations))
            if turns.count > 10 {
                turns.removeFirst(turns.count - 10)
            }
            statusText = "Ask Memory 已完成"
            AppLogStore.shared.info(
                "\(scope.label)问答已完成，引用记录 \(sourceItems.count) 条。",
                category: "Ask Memory"
            )
        } catch {
            statusText = error.localizedDescription
            AppLogStore.shared.error(
                "\(scope.label)问答失败：\(error.localizedDescription)",
                category: "Ask Memory"
            )
        }
    }

    private var conversationContext: String {
        turns.suffix(5).map { turn in
            "用户：\(turn.question)\n助手：\(turn.answer.clipped(to: 800))"
        }.joined(separator: "\n\n")
    }
}
