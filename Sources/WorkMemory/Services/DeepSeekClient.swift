import Foundation

struct DeepSeekClient {
    private let defaultMaxTokens = 4_000
    private let requestTimeout: TimeInterval = 120

    struct Configuration {
        var apiKey: String
        var baseURL: String
        var model: String
    }

    enum ClientError: LocalizedError {
        case missingAPIKey
        case invalidBaseURL
        case invalidResponse
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "请先填写模型 API Key"
            case .invalidBaseURL:
                return "模型 API Base URL 无效"
            case .invalidResponse:
                return "模型 API 返回格式无法解析"
            case .apiError(let message):
                return message
            }
        }
    }

    func testConnection(configuration: Configuration) async throws -> String {
        let response = try await complete(
            messages: [
                .init(role: "system", content: "你是 API 连通性测试助手，只输出 OK。"),
                .init(role: "user", content: "请回复 OK")
            ],
            configuration: configuration,
            temperature: 0,
            maxTokens: 16
        )
        return response.clipped(to: 80)
    }

    func summarizeDailyRecords(
        items: [MemoryItem],
        configuration: Configuration
    ) async throws -> String {
        try await complete(
            messages: [
                .init(role: "system", content: dailySummarySystemPrompt),
                .init(role: "user", content: dailySummaryUserPrompt(for: items))
            ],
            configuration: configuration,
            temperature: 0.2,
            maxTokens: defaultMaxTokens
        )
    }

    func summarizeSelectedRecords(
        items: [MemoryItem],
        configuration: Configuration
    ) async throws -> String {
        try await complete(
            messages: [
                .init(role: "system", content: selectedSummarySystemPrompt),
                .init(role: "user", content: selectedSummaryUserPrompt(for: items))
            ],
            configuration: configuration,
            temperature: 0.15,
            maxTokens: defaultMaxTokens
        )
    }

    func summarizeWebPages(
        items: [MemoryItem],
        range: WebSummaryRange,
        configuration: Configuration
    ) async throws -> String {
        try await complete(
            messages: [
                .init(role: "system", content: webSummarySystemPrompt),
                .init(role: "user", content: webSummaryUserPrompt(for: items, range: range))
            ],
            configuration: configuration,
            temperature: 0.15,
            maxTokens: defaultMaxTokens
        )
    }

    func askMemory(
        question: String,
        items: [MemoryItem],
        scope: MemoryQueryScope,
        conversationContext: String = "",
        configuration: Configuration
    ) async throws -> String {
        try await complete(
            messages: [
                .init(role: "system", content: askMemorySystemPrompt),
                .init(
                    role: "user",
                    content: askMemoryUserPrompt(
                        question: question,
                        items: items,
                        scope: scope,
                        conversationContext: conversationContext
                    )
                )
            ],
            configuration: configuration,
            temperature: 0.1,
            maxTokens: defaultMaxTokens
        )
    }

    func extractActionItems(
        items: [MemoryItem],
        configuration: Configuration
    ) async throws -> [ActionItemSuggestion] {
        let rawResponse = try await complete(
            messages: [
                .init(role: "system", content: actionExtractionSystemPrompt),
                .init(role: "user", content: actionExtractionUserPrompt(for: items))
            ],
            configuration: configuration,
            temperature: 0.1,
            maxTokens: defaultMaxTokens
        )

        let jsonText = extractJSONArray(from: rawResponse)
        guard let jsonData = jsonText.data(using: .utf8) else {
            AppLogStore.shared.error(
                """
                行动项抽取结果无法转成 JSON 数据
                模型响应：
                \(rawResponse.clipped(to: 2_000))
                """,
                category: "模型 API"
            )
            throw ClientError.apiError("行动项抽取结果无法解析，详情见运行日志。")
        }

        do {
            return try JSONDecoder().decode([ActionItemSuggestion].self, from: jsonData)
        } catch {
            AppLogStore.shared.error(
                """
                行动项抽取 JSON 解析失败
                错误：\(error.localizedDescription)
                JSON：
                \(jsonText.clipped(to: 2_000))
                原始响应：
                \(rawResponse.clipped(to: 2_000))
                """,
                category: "模型 API"
            )
            throw ClientError.apiError("行动项抽取 JSON 解析失败：\(oneLine(error.localizedDescription))。详情见运行日志。")
        }
    }

    func summarizeDocument(
        fileName: String,
        filePath: String,
        modifiedAt: Date,
        extractedText: String,
        configuration: Configuration
    ) async throws -> String {
        try await complete(
            messages: [
                .init(role: "system", content: documentSummarySystemPrompt),
                .init(
                    role: "user",
                    content: documentSummaryUserPrompt(
                        fileName: fileName,
                        filePath: filePath,
                        modifiedAt: modifiedAt,
                        extractedText: extractedText
                    )
                )
            ],
            configuration: configuration,
            temperature: 0.15,
            maxTokens: defaultMaxTokens
        )
    }

    private func complete(
        messages: [ChatMessage],
        configuration: Configuration,
        temperature: Double,
        maxTokens: Int
    ) async throws -> String {
        guard !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            AppLogStore.shared.warning("缺少模型 API Key，已取消请求。", category: "模型 API")
            throw ClientError.missingAPIKey
        }

        guard let endpoint = chatCompletionsEndpoint(baseURL: configuration.baseURL) else {
            AppLogStore.shared.error(
                """
                模型 API Base URL 无效
                Base URL：\(configuration.baseURL)
                Model：\(configuration.model)
                """,
                category: "模型 API"
            )
            throw ClientError.invalidBaseURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ChatCompletionRequest(
            model: configuration.model,
            messages: messages,
            stream: false,
            temperature: temperature,
            maxTokens: maxTokens
        )

        let requestSummary = """
        Endpoint：\(endpoint.absoluteString)
        Model：\(configuration.model)
        Messages：\(messages.count)
        Temperature：\(temperature)
        Max tokens：\(maxTokens)
        """

        AppLogStore.shared.info(
            """
            开始调用模型 API
            \(requestSummary)
            """,
            category: "模型 API"
        )

        do {
            request.httpBody = try JSONEncoder().encode(body)
            let startedAt = Date()
            let (data, response) = try await dataWithRetry(for: request)
            let elapsedText = String(format: "%.2f", Date().timeIntervalSince(startedAt))

            guard let httpResponse = response as? HTTPURLResponse else {
                AppLogStore.shared.error(
                    """
                    模型 API 返回了非 HTTP 响应
                    \(requestSummary)
                    Response bytes：\(data.count)
                    """,
                    category: "模型 API"
                )
                throw ClientError.apiError("模型 API 返回了非 HTTP 响应，详情见运行日志。")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let apiMessage = parseAPIError(from: data) ?? "响应体中没有可解析的错误信息"
                AppLogStore.shared.error(
                    """
                    模型 API 请求失败
                    HTTP 状态：\(httpResponse.statusCode)
                    耗时：\(elapsedText) 秒
                    \(requestSummary)
                    错误信息：\(apiMessage)
                    响应体：
                    \(responseBodyText(from: data).clipped(to: 2_000))
                    """,
                    category: "模型 API"
                )
                throw ClientError.apiError(
                    "模型 API 请求失败：HTTP \(httpResponse.statusCode)，\(oneLine(apiMessage).clipped(to: 180))。详情见运行日志。"
                )
            }

            let decoded: ChatCompletionResponse
            do {
                decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            } catch {
                AppLogStore.shared.error(
                    """
                    模型 API 返回格式无法解析
                    HTTP 状态：\(httpResponse.statusCode)
                    耗时：\(elapsedText) 秒
                    \(requestSummary)
                    解析错误：\(error.localizedDescription)
                    响应体：
                    \(responseBodyText(from: data).clipped(to: 2_000))
                    """,
                    category: "模型 API"
                )
                throw ClientError.apiError(
                    "模型 API 返回格式无法解析：\(oneLine(error.localizedDescription).clipped(to: 180))。详情见运行日志。"
                )
            }

            guard let content = decoded.choices.first?.message.content.nilIfBlank else {
                AppLogStore.shared.error(
                    """
                    模型 API 返回内容为空
                    HTTP 状态：\(httpResponse.statusCode)
                    耗时：\(elapsedText) 秒
                    \(requestSummary)
                    响应体：
                    \(responseBodyText(from: data).clipped(to: 2_000))
                    """,
                    category: "模型 API"
                )
                throw ClientError.apiError("模型 API 返回内容为空，详情见运行日志。")
            }

            AppLogStore.shared.info(
                """
                模型 API 请求成功
                HTTP 状态：\(httpResponse.statusCode)
                耗时：\(elapsedText) 秒
                \(requestSummary)
                输出字符数：\(content.count)
                """,
                category: "模型 API"
            )

            return content
        } catch let error as ClientError {
            throw error
        } catch {
            AppLogStore.shared.error(
                """
                模型 API 网络或请求错误
                \(requestSummary)
                错误类型：\(type(of: error))
                错误信息：\(error.localizedDescription)
                """,
                category: "模型 API"
            )
            throw ClientError.apiError(
                "模型 API 网络或请求错误：\(oneLine(error.localizedDescription).clipped(to: 180))。详情见运行日志。"
            )
        }
    }

    private func dataWithRetry(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask {
                try await performDataWithRetry(for: request)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 180 * 1_000_000_000)
                throw URLError(.timedOut)
            }
            guard let result = try await group.next() else { throw URLError(.unknown) }
            group.cancelAll()
            return result
        }
    }

    private func performDataWithRetry(for request: URLRequest) async throws -> (Data, URLResponse) {
        var lastError: Error?
        for attempt in 1...3 {
            try Task.checkCancellation()
            do {
                let result = try await URLSession.shared.data(for: request)
                if let response = result.1 as? HTTPURLResponse,
                   (response.statusCode == 408 || response.statusCode == 429 || (500..<600).contains(response.statusCode)),
                   attempt < 3 {
                    try await Task.sleep(nanoseconds: UInt64(350 * pow(2, Double(attempt - 1))) * 1_000_000)
                    continue
                }
                return result
            } catch {
                if error is CancellationError { throw error }
                lastError = error
                guard attempt < 3, isRetryableNetworkError(error) else { throw error }
                try await Task.sleep(nanoseconds: UInt64(350 * pow(2, Double(attempt - 1))) * 1_000_000)
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    private func isRetryableNetworkError(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [
            .timedOut, .networkConnectionLost, .cannotConnectToHost,
            .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet
        ].contains(error.code)
    }

    private var dailySummarySystemPrompt: String {
        """
        你是一个严谨的个人工作记忆分析助手。你的任务是把用户一天中自动采集和手动记录的内容整理成可执行的工作复盘。
        要求：
        - 用中文输出。
        - 不要编造记录中没有的信息。
        - 明确区分事实、推断和建议。
        - 重点提炼行动项、决策、问题、风险、可沉淀文档。
        - 除“今日摘要”外，优先使用标准 Markdown 表格输出，表格必须包含表头分隔行。
        - 输出结构必须清晰，适合直接保存到工作日志。
        """
    }

    private func dailySummaryUserPrompt(for items: [MemoryItem]) -> String {
        let records = items.enumerated().map { index, item in
            """
            [\(index + 1)]
            时间：\(DateFormatting.dateTime.string(from: item.createdAt))
            分类：\(item.category.label)
            来源：\(item.context?.source.label ?? "手动")
            上下文：\(item.context?.summary ?? "无")
            标题：\(item.title)
            内容：
            \(item.content.clipped(to: 1_200))
            """
        }.joined(separator: "\n\n---\n\n")

        return """
        请总结今天的 WorkMemory 记录。

        请按以下结构输出：

        # 今日摘要
        用 3-5 条说明今天主要发生了什么、我主要在关注什么。

        # 关键想法
        使用 Markdown 表格：主题｜内容｜价值｜来源记录。

        # 待推进事项
        使用 Markdown 表格：事项｜对象/项目｜下一步｜优先级｜来源记录。

        # 决策与结论
        使用 Markdown 表格：结论｜依据｜影响｜来源记录。

        # 问题与风险
        使用 Markdown 表格：问题/风险｜表现｜建议处理｜来源记录。

        # 值得沉淀成文档
        使用 Markdown 表格：文档主题｜适合类型｜应包含内容｜来源记录。

        # 明日建议
        使用 Markdown 表格：建议｜原因｜预期结果。

        今日记录如下：

        \(records)
        """
    }

    private var selectedSummarySystemPrompt: String {
        """
        你是一个严谨的个人工作记忆分析助手。用户会手动选择少量记录让你总结，以节省模型用量。
        要求：
        - 用中文输出。
        - 只依据用户选择的记录，不要扩展到未提供的内容。
        - 明确区分事实、推断和建议。
        - 重点提炼主题、关键结论、行动项、风险问题、可沉淀文档。
        - 除摘要段落外，优先使用标准 Markdown 表格输出，表格必须包含表头分隔行。
        - 输出结构清晰，适合保存为一条工作记忆。
        """
    }

    private func selectedSummaryUserPrompt(for items: [MemoryItem]) -> String {
        let records = formattedRecords(items, contentLimit: 1_800)

        return """
        请总结以下手动选择的 WorkMemory 记录。

        请按以下结构输出：

        # 精选记录摘要
        用 3-5 条概括这些记录共同说明了什么。

        # 关键结论
        使用 Markdown 表格：结论｜依据｜影响｜来源记录。

        # 待推进事项
        使用 Markdown 表格：事项｜对象/项目｜下一步｜优先级｜来源记录。

        # 问题与风险
        使用 Markdown 表格：问题/风险｜表现｜建议处理｜来源记录。

        # 可沉淀内容
        使用 Markdown 表格：主题｜适合类型｜应包含内容｜来源记录。

        # 建议下一步
        使用 Markdown 表格：建议｜原因｜预期结果。

        手动选择的记录如下：

        \(records)
        """
    }

    private var askMemorySystemPrompt: String {
        """
        你是 WorkMemory 的问答助手。你只能依据给定记录回答问题。
        要求：
        - 用中文回答。
        - 不知道就说“不确定”，不要编造。
        - 回答要直接、可执行。
        - 关键结论后用 [记录编号] 标注来源。
        - 如果问题涉及任务、风险、决策，优先列成清单。
        """
    }

    private var webSummarySystemPrompt: String {
        """
        你是 WorkMemory 的网页阅读总结助手。你的任务是把用户一段时间内浏览过的网页记录整理成有用的工作情报。
        要求：
        - 用中文输出。
        - 只能依据网页标题、URL 和已采集正文摘录总结，不要编造网页里没有的信息。
        - 区分“明确来自网页内容的信息”和“基于浏览行为推断的关注方向”。
        - 合并重复网页和相近主题。
        - 除摘要段落外，优先使用标准 Markdown 表格输出，表格必须包含表头分隔行。
        - 输出要适合保存为工作记忆。
        """
    }

    private func webSummaryUserPrompt(for items: [MemoryItem], range: WebSummaryRange) -> String {
        let records = items.enumerated().map { index, item in
            """
            [\(index + 1)]
            时间：\(DateFormatting.dateTime.string(from: item.createdAt))
            浏览器：\(item.context?.appName ?? "未知")
            标题：\(item.context?.pageTitle ?? item.title)
            URL：\(item.context?.url ?? "无")
            内容：
            \(item.content.clipped(to: 2_000))
            """
        }.joined(separator: "\n\n---\n\n")

        return """
        请总结\(range.label)浏览过的网页内容。

        请按以下结构输出：

        # 网页浏览摘要
        用 3-5 条说明这段时间主要看了哪些主题。

        # 重要网页
        使用 Markdown 表格：网页标题｜为什么重要｜URL｜来源记录。

        # 关键信息
        使用 Markdown 表格：信息｜类型｜对工作的价值｜来源记录。

        # 可能关联到工作的方向
        使用 Markdown 表格：推断方向｜依据｜建议验证方式。

        # 待跟进
        使用 Markdown 表格：事项｜动作｜原因｜优先级。

        网页记录如下：

        \(records)
        """
    }

    private func askMemoryUserPrompt(
        question: String,
        items: [MemoryItem],
        scope: MemoryQueryScope,
        conversationContext: String
    ) -> String {
        let records = formattedRecords(items, contentLimit: 1_000)

        return """
        查询范围：\(scope.label)
        用户问题：\(question)

        最近对话：
        \(conversationContext.nilIfBlank ?? "无")

        请基于下面记录回答。重要结论必须带 [记录编号]。

        \(records)
        """
    }

    private var actionExtractionSystemPrompt: String {
        """
        你是一个行动项抽取器。你的任务是从 WorkMemory 记录中提取明确需要推进的事项。
        严格要求：
        - 只输出 JSON 数组，不要输出 Markdown，不要解释。
        - 不要编造记录中没有的任务。
        - 合并重复任务。
        - dueDate 使用 ISO 8601（例如 2026-07-12T18:00:00+08:00）；不明确则为空字符串。
        - priority 只能是 low、normal、high、urgent；不明确时使用 normal。
        - 如果项目、负责人、截止时间不明确，输出空字符串。
        - sourceIndex 使用最能支持该任务的记录编号。
        JSON 字段：title, project, owner, dueDateText, dueDate, priority, evidence, sourceIndex
        """
    }

    private var documentSummarySystemPrompt: String {
        """
        你是 WorkMemory 的本地文档分析助手。你的任务是把一个本地文档转成可进入今日工作记忆的摘要。
        要求：
        - 用中文输出。
        - 不要编造文档中没有的信息。
        - 重点提炼核心内容、关键结论、待跟进事项、风险问题、可沉淀内容。
        - 如果文档内容不足或像乱码，要明确说明。
        - 除“文档摘要”外，优先使用标准 Markdown 表格输出，表格必须包含表头分隔行。
        - 输出结构固定、简洁、适合保存为一条工作记忆。
        """
    }

    private func documentSummaryUserPrompt(
        fileName: String,
        filePath: String,
        modifiedAt: Date,
        extractedText: String
    ) -> String {
        """
        请总结以下本地文档，并按结构输出：

        # 文档摘要
        - 文件：\(fileName)
        - 路径：\(filePath)
        - 更新时间：\(DateFormatting.dateTime.string(from: modifiedAt))

        # 核心内容
        使用 Markdown 表格：模块｜内容｜价值。

        # 关键结论
        使用 Markdown 表格：结论｜依据｜影响。

        # 待跟进事项
        使用 Markdown 表格：事项｜下一步｜负责人/对象｜优先级。

        # 风险/问题
        使用 Markdown 表格：风险/问题｜表现｜建议处理。

        # 可沉淀内容
        使用 Markdown 表格：主题｜适合类型｜应包含内容。

        文档正文如下：

        \(extractedText.clipped(to: 16_000))
        """
    }

    private func actionExtractionUserPrompt(for items: [MemoryItem]) -> String {
        """
        请从以下记录提取行动项，输出 JSON 数组。

        示例：
        [
          {
            "title": "确认 DeepSeek API 总结功能是否能正常调用",
            "project": "WorkMemory",
            "owner": "",
            "dueDateText": "",
            "dueDate": "",
            "priority": "normal",
            "evidence": "用户要求接入 DeepSeek API 并支持手动总结和 18:00 自动总结",
            "sourceIndex": 1
          }
        ]

        记录：

        \(formattedRecords(items, contentLimit: 900))
        """
    }

    private func formattedRecords(_ items: [MemoryItem], contentLimit: Int) -> String {
        items.enumerated().map { index, item in
            """
            [\(index + 1)]
            id：\(item.id.uuidString)
            时间：\(DateFormatting.dateTime.string(from: item.createdAt))
            分类：\(item.category.label)
            来源：\(item.context?.source.label ?? "手动")
            上下文：\(item.context?.summary ?? "无")
            标题：\(item.title)
            内容：
            \(item.content.clipped(to: contentLimit))
            """
        }.joined(separator: "\n\n---\n\n")
    }

    private func normalizedBaseURL(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func chatCompletionsEndpoint(baseURL: String) -> URL? {
        guard let url = URL(string: normalizedBaseURL(baseURL) + "/chat/completions"),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              url.host?.nilIfBlank != nil else {
            return nil
        }
        return url
    }

    private func oneLine(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func responseBodyText(from data: Data) -> String {
        String(data: data, encoding: .utf8)?.nilIfBlank ?? "<\(data.count) bytes binary response>"
    }

    private func parseAPIError(from data: Data) -> String? {
        guard let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) else {
            return String(data: data, encoding: .utf8)?.nilIfBlank
        }

        return errorResponse.error.message.nilIfBlank
    }

    private func extractJSONArray(from text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let start = cleaned.firstIndex(of: "["),
              let end = cleaned.lastIndex(of: "]"),
              start <= end else {
            return cleaned
        }

        return String(cleaned[start...end])
    }
}

private struct ChatCompletionRequest: Encodable {
    var model: String
    var messages: [ChatMessage]
    var stream: Bool
    var temperature: Double
    var maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case temperature
        case maxTokens = "max_tokens"
    }
}

private struct ChatMessage: Codable {
    var role: String
    var content: String
}

private struct ChatCompletionResponse: Decodable {
    var choices: [Choice]

    struct Choice: Decodable {
        var message: ChatMessage
    }
}

private struct APIErrorResponse: Decodable {
    var error: APIError

    struct APIError: Decodable {
        var message: String
    }
}
