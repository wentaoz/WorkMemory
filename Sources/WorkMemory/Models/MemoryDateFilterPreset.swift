import Foundation

enum MemoryDateFilterPreset: String, CaseIterable, Identifiable {
    case all
    case today
    case yesterday
    case lastSevenDays
    case lastThirtyDays
    case thisMonth
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            return "全部日期"
        case .today:
            return "今天"
        case .yesterday:
            return "昨天"
        case .lastSevenDays:
            return "近 7 天"
        case .lastThirtyDays:
            return "近 30 天"
        case .thisMonth:
            return "本月"
        case .custom:
            return "自定义"
        }
    }

    var usesCustomRange: Bool {
        self == .custom
    }

    func contains(_ date: Date, customStartDate: Date, customEndDate: Date) -> Bool {
        guard let range = dateRange(customStartDate: customStartDate, customEndDate: customEndDate) else {
            return true
        }

        return date >= range.start && date < range.end
    }

    func dateRange(customStartDate: Date, customEndDate: Date) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .all:
            return nil
        case .today:
            let start = calendar.startOfDay(for: now)
            return (start, calendar.date(byAdding: .day, value: 1, to: start) ?? now)
        case .yesterday:
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            return (start, today)
        case .lastSevenDays:
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            let start = calendar.date(byAdding: .day, value: -7, to: end) ?? now
            return (start, end)
        case .lastThirtyDays:
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            let start = calendar.date(byAdding: .day, value: -30, to: end) ?? now
            return (start, end)
        case .thisMonth:
            let components = calendar.dateComponents([.year, .month], from: now)
            let start = calendar.date(from: components) ?? calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? now
            return (start, end)
        case .custom:
            let start = calendar.startOfDay(for: min(customStartDate, customEndDate))
            let endBase = calendar.startOfDay(for: max(customStartDate, customEndDate))
            let end = calendar.date(byAdding: .day, value: 1, to: endBase) ?? endBase
            return (start, end)
        }
    }

    func rangeDescription(customStartDate: Date, customEndDate: Date) -> String {
        guard let range = dateRange(customStartDate: customStartDate, customEndDate: customEndDate) else {
            return "不过滤日期"
        }

        let inclusiveEnd = Calendar.current.date(byAdding: .day, value: -1, to: range.end) ?? range.end
        return "\(DateFormatting.mediumDate.string(from: range.start)) - \(DateFormatting.mediumDate.string(from: inclusiveEnd))"
    }
}
