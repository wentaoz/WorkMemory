import SwiftUI

struct SummaryWorkspaceView: View {
    @EnvironmentObject private var store: MemoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AISummaryControlView()

            WebSummaryControlView()

            runHistory

            MemoryListView(title: "总结历史", items: store.summaryHistory)
        }
    }

    @ViewBuilder
    private var runHistory: some View {
        if !store.summaryRuns.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("最近运行").font(.headline)
                ForEach(store.summaryRuns.prefix(8)) { run in
                    HStack(spacing: 10) {
                        Image(systemName: run.status.systemImage)
                            .foregroundStyle(run.status.color)
                            .frame(width: 18)
                        Text(run.kind.label)
                            .font(.callout.weight(.medium))
                        Text("\(run.sourceCount) 条来源")
                        Text(DateFormatting.dateTime.string(from: run.createdAt))
                        if !run.errorMessage.isEmpty {
                            Text(run.errorMessage).lineLimit(1)
                        }
                        Spacer()
                        Text(run.status.label)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 3)
                }
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private extension SummaryRunKind {
    var label: String {
        switch self {
        case .daily: return "今日总结"
        case .selected: return "精选总结"
        case .web: return "网页总结"
        case .document: return "文档总结"
        }
    }
}

private extension SummaryRunStatus {
    var label: String {
        switch self {
        case .waiting: return "等待"
        case .running: return "运行中"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }

    var systemImage: String {
        switch self {
        case .waiting: return "clock"
        case .running: return "hourglass"
        case .completed: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        case .cancelled: return "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        case .waiting, .running: return .orange
        }
    }
}
