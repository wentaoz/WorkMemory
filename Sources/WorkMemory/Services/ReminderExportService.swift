import EventKit
import Foundation

@MainActor
final class ReminderExportService: ObservableObject {
    @Published private(set) var statusText = "尚未同步提醒事项"
    @Published private(set) var isExporting = false

    private let store = EKEventStore()

    func export(_ item: WorkActionItem) async throws -> String {
        guard !isExporting else { throw ReminderExportError.busy }
        isExporting = true
        defer { isExporting = false }
        guard try await requestAccess() else {
            statusText = "未获得提醒事项权限"
            throw ReminderExportError.permissionDenied
        }

        let reminder: EKReminder
        if let identifier = item.reminderIdentifier,
           let existing = store.calendarItem(withIdentifier: identifier) as? EKReminder {
            reminder = existing
        } else {
            reminder = EKReminder(eventStore: store)
            reminder.calendar = try workMemoryCalendar()
        }
        reminder.title = item.title
        reminder.notes = [item.project.nilIfBlank, item.evidence.nilIfBlank, item.sourceTitle.nilIfBlank]
            .compactMap { $0 }
            .joined(separator: "\n\n")
        if let dueDate = item.dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        } else {
            reminder.dueDateComponents = nil
        }
        try store.save(reminder, commit: true)
        statusText = item.reminderIdentifier == nil ? "已加入提醒事项" : "提醒事项已更新"
        return reminder.calendarItemIdentifier
    }

    private func requestAccess() async throws -> Bool {
        if #available(macOS 14.0, *) {
            return try await store.requestFullAccessToReminders()
        }
        return try await withCheckedThrowingContinuation { continuation in
            store.requestAccess(to: .reminder) { granted, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: granted) }
            }
        }
    }

    private func workMemoryCalendar() throws -> EKCalendar {
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == "WorkMemory" }) {
            return existing
        }
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = "WorkMemory"
        calendar.source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first(where: { $0.sourceType == .local || $0.sourceType == .calDAV })
        guard calendar.source != nil else { throw ReminderExportError.noWritableCalendar }
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }
}

enum ReminderExportError: LocalizedError {
    case busy
    case permissionDenied
    case noWritableCalendar

    var errorDescription: String? {
        switch self {
        case .busy: return "提醒事项正在同步"
        case .permissionDenied: return "请在系统设置中允许 WorkMemory 访问提醒事项"
        case .noWritableCalendar: return "没有可写入的提醒事项列表"
        }
    }
}
