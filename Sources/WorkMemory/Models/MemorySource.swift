import Foundation

enum MemorySource: String, Codable, CaseIterable, Identifiable {
    case manual
    case voice
    case typing
    case browser
    case activeWindow
    case ocr
    case aiSummary
    case localDocument

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual:
            return "手动"
        case .voice:
            return "语音"
        case .typing:
            return "输入"
        case .browser:
            return "网页"
        case .activeWindow:
            return "窗口"
        case .ocr:
            return "OCR"
        case .aiSummary:
            return "AI 总结"
        case .localDocument:
            return "本地文档"
        }
    }

    var systemImage: String {
        switch self {
        case .manual:
            return "keyboard"
        case .voice:
            return "mic"
        case .typing:
            return "text.cursor"
        case .browser:
            return "safari"
        case .activeWindow:
            return "macwindow"
        case .ocr:
            return "viewfinder"
        case .aiSummary:
            return "sparkles"
        case .localDocument:
            return "doc.text.magnifyingglass"
        }
    }
}
