import Foundation

enum SidebarSelection: Hashable {
    case today
    case all
    case summaries
    case askMemory
    case actions
    case logs
    case settings
    case category(MemoryCategory)

    var id: String {
        switch self {
        case .today:
            return "today"
        case .all:
            return "all"
        case .summaries:
            return "summaries"
        case .askMemory:
            return "ask-memory"
        case .actions:
            return "actions"
        case .logs:
            return "logs"
        case .settings:
            return "settings"
        case .category(let category):
            return "category:\(category.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .today:
            return "今日工作记忆"
        case .all:
            return "全部记录"
        case .summaries:
            return "AI 总结"
        case .askMemory:
            return "Ask Memory"
        case .actions:
            return "行动项"
        case .logs:
            return "运行日志"
        case .settings:
            return "设置"
        case .category(let category):
            return category.label
        }
    }

    static func from(id: String) -> SidebarSelection {
        if id == "today" { return .today }
        if id == "all" { return .all }
        if id == "summaries" { return .summaries }
        if id == "ask-memory" { return .askMemory }
        if id == "actions" { return .actions }
        if id == "logs" { return .logs }
        if id == "settings" { return .settings }

        if id.hasPrefix("category:") {
            let rawValue = String(id.dropFirst("category:".count))
            if let category = MemoryCategory(rawValue: rawValue) {
                return .category(category)
            }
        }

        return .today
    }
}
