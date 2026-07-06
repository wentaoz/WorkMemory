import Foundation

enum WebSummaryRange: String, CaseIterable, Identifiable {
    case today
    case lastThreeDays
    case lastSevenDays
    case lastThirtyDays
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today:
            return "今天"
        case .lastThreeDays:
            return "近 3 天"
        case .lastSevenDays:
            return "近 7 天"
        case .lastThirtyDays:
            return "近 30 天"
        case .all:
            return "全部"
        }
    }

    var startDate: Date? {
        switch self {
        case .today:
            return Calendar.current.startOfDay(for: Date())
        case .lastThreeDays:
            return Calendar.current.date(byAdding: .day, value: -3, to: Date())
        case .lastSevenDays:
            return Calendar.current.date(byAdding: .day, value: -7, to: Date())
        case .lastThirtyDays:
            return Calendar.current.date(byAdding: .day, value: -30, to: Date())
        case .all:
            return nil
        }
    }
}
