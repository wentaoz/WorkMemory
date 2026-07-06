import Foundation

struct MemoryAnalysis {
    var title: String
    var category: MemoryCategory
    var actionItems: [String]
}

struct MemoryClassifier {
    func analyze(_ content: String) -> MemoryAnalysis {
        MemoryAnalysis(
            title: makeTitle(from: content),
            category: classify(content),
            actionItems: extractActionItems(from: content)
        )
    }

    private func makeTitle(from content: String) -> String {
        let firstLine = content
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        ?? "Untitled"

        guard firstLine.count > 36 else { return firstLine }
        return String(firstLine.prefix(36)) + "..."
    }

    private func classify(_ content: String) -> MemoryCategory {
        let text = content.lowercased()

        if containsAny(text, ["会议", "meeting", "同步", "纪要", "讨论"]) {
            return .meeting
        }

        if containsAny(text, ["决定", "确认", "拍板", "结论", "decision", "最终"]) {
            return .decision
        }

        if containsAny(text, ["要做", "待办", "todo", "记得", "提醒", "跟进", "安排", "下周", "明天", "联系"]) {
            return .task
        }

        if containsAny(text, ["为什么", "怎么", "是否", "问题", "风险", "?", "？", "blocker"]) {
            return .question
        }

        if containsAny(text, ["项目", "需求", "prd", "客户", "版本", "roadmap", "方案"]) {
            return .project
        }

        if containsAny(text, ["想法", "灵感", "可以做", "我在想", "idea", "maybe"]) {
            return .idea
        }

        return .note
    }

    private func extractActionItems(from content: String) -> [String] {
        let separators = CharacterSet(charactersIn: "\n。.!！?？；;")
        return content
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { sentence in
                containsAny(sentence.lowercased(), ["要", "需要", "待办", "todo", "记得", "提醒", "跟进", "安排", "联系", "确认"])
            }
            .prefix(5)
            .map { sentence in
                sentence.count > 56 ? String(sentence.prefix(56)) + "..." : sentence
            }
    }

    private func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }
}
