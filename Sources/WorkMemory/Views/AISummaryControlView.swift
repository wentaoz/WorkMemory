import SwiftUI

struct AISummaryControlView: View {
    @EnvironmentObject private var dailySummary: DailySummaryService
    @EnvironmentObject private var store: MemoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    header
                    Spacer()
                    summaryActions
                }

                VStack(alignment: .leading, spacing: 10) {
                    header
                    summaryActions
                }
            }

            HStack(spacing: 16) {
                Label(dailySummary.statusText, systemImage: dailySummary.isSummarizing ? "hourglass" : "info.circle")
                    .foregroundStyle(.secondary)

                Divider()
                    .frame(height: 16)

                Label("今天可总结 \(store.todaySourceItemsForSummary.count) 条", systemImage: "doc.text.magnifyingglass")
                    .foregroundStyle(.secondary)

                Divider()
                    .frame(height: 16)

                Label("已选 \(store.selectedForSummaryCount) 条", systemImage: "checklist.checked")
                    .foregroundStyle(store.selectedForSummaryCount > 0 ? Color.accentColor : Color.secondary)

                if let lastSummaryAt = dailySummary.lastSummaryAt {
                    Text(DateFormatting.time.string(from: lastSummaryAt))
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption)

            if dailySummary.isSummarizing {
                HStack(spacing: 10) {
                    ProgressView(value: dailySummary.progress)
                    Text("\(Int(dailySummary.progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button {
                        dailySummary.cancel()
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("取消总结")
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        Label("AI 总结", systemImage: "sparkles")
            .font(.headline)
    }

    private var summaryActions: some View {
        HStack(spacing: 10) {
            Button {
                dailySummary.summarizeSelectedManually()
            } label: {
                Label("总结已选", systemImage: "checklist.checked")
            }
            .disabled(dailySummary.isSummarizing || store.selectedForSummaryCount == 0)

            Button {
                dailySummary.summarizeTodayManually()
            } label: {
                Label(dailySummary.isSummarizing ? "总结中" : "总结今日", systemImage: "wand.and.stars")
            }
            .disabled(dailySummary.isSummarizing || store.todaySourceItemsForSummary.isEmpty)
        }
    }
}
