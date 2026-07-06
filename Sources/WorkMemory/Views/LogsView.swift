import AppKit
import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var logStore: AppLogStore
    @State private var filter: LogLevelFilter = .all
    @State private var searchText = ""

    private var visibleEntries: [AppLogEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return logStore.entries.filter { entry in
            filter.matches(entry)
            && (
                query.isEmpty
                || entry.category.localizedCaseInsensitiveContains(query)
                || entry.message.localizedCaseInsensitiveContains(query)
                || entry.level.label.localizedCaseInsensitiveContains(query)
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            controls

            if visibleEntries.isEmpty {
                EmptyStateView(
                    title: logStore.entries.isEmpty ? "还没有运行日志" : "没有匹配的日志",
                    message: "模型 API 调用、摘要任务和后续错误会在这里显示，方便排查问题。"
                )
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleEntries) { entry in
                        LogEntryRowView(entry: entry)
                    }
                }
            }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Label("运行日志", systemImage: "list.bullet.rectangle")
                    .font(.headline)

                Text("\(logStore.entries.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
                logActions
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Label("运行日志", systemImage: "list.bullet.rectangle")
                        .font(.headline)

                    Text("\(logStore.entries.count) 条")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                logActions
            }
        }
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Picker("级别", selection: $filter) {
                    ForEach(LogLevelFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                TextField("搜索日志", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                Picker("级别", selection: $filter) {
                    ForEach(LogLevelFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                TextField("搜索日志", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var logActions: some View {
        HStack(spacing: 10) {
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(logStore.copyText(), forType: .string)
            } label: {
                Label("复制日志", systemImage: "doc.on.doc")
            }
            .disabled(logStore.entries.isEmpty)

            Button(role: .destructive) {
                logStore.clear()
            } label: {
                Label("清空", systemImage: "trash")
            }
            .disabled(logStore.entries.isEmpty)
        }
    }
}

private struct LogEntryRowView: View {
    let entry: AppLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(entry.level.label, systemImage: entry.level.systemImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(entry.level.tint)

                Text(entry.category)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(DateFormatting.dateTime.string(from: entry.createdAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private enum LogLevelFilter: String, CaseIterable, Identifiable {
    case all
    case info
    case warning
    case error

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            return "全部"
        case .info:
            return AppLogLevel.info.label
        case .warning:
            return AppLogLevel.warning.label
        case .error:
            return AppLogLevel.error.label
        }
    }

    func matches(_ entry: AppLogEntry) -> Bool {
        switch self {
        case .all:
            return true
        case .info:
            return entry.level == .info
        case .warning:
            return entry.level == .warning
        case .error:
            return entry.level == .error
        }
    }
}

private extension AppLogLevel {
    var systemImage: String {
        switch self {
        case .info:
            return "info.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.octagon"
        }
    }

    var tint: Color {
        switch self {
        case .info:
            return .blue
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}
