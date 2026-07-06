import Foundation

enum MemoryQueryScope: String, CaseIterable, Identifiable {
    case today
    case lastSevenDays
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today:
            return "今天"
        case .lastSevenDays:
            return "最近 7 天"
        case .all:
            return "全部"
        }
    }
}
