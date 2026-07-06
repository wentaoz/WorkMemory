import SwiftUI

enum MemoryCategory: String, CaseIterable, Codable, Identifiable {
    case idea
    case task
    case decision
    case question
    case meeting
    case project
    case web
    case context
    case summary
    case document
    case note

    var id: String { rawValue }

    var label: String {
        switch self {
        case .idea:
            return "想法"
        case .task:
            return "待办"
        case .decision:
            return "决策"
        case .question:
            return "问题"
        case .meeting:
            return "会议"
        case .project:
            return "项目"
        case .web:
            return "网页"
        case .context:
            return "上下文"
        case .summary:
            return "总结"
        case .document:
            return "文档"
        case .note:
            return "记录"
        }
    }

    var systemImage: String {
        switch self {
        case .idea:
            return "lightbulb"
        case .task:
            return "checkmark.circle"
        case .decision:
            return "seal"
        case .question:
            return "questionmark.circle"
        case .meeting:
            return "person.2"
        case .project:
            return "folder"
        case .web:
            return "globe"
        case .context:
            return "scope"
        case .summary:
            return "sparkles"
        case .document:
            return "doc.text"
        case .note:
            return "note.text"
        }
    }

    var tint: Color {
        switch self {
        case .idea:
            return .yellow
        case .task:
            return .green
        case .decision:
            return .blue
        case .question:
            return .orange
        case .meeting:
            return .indigo
        case .project:
            return .teal
        case .web:
            return .blue
        case .context:
            return .cyan
        case .summary:
            return .purple
        case .document:
            return .mint
        case .note:
            return .secondary
        }
    }
}
