import SwiftUI

struct WebSummaryControlView: View {
    @EnvironmentObject private var store: MemoryStore
    @EnvironmentObject private var webSummary: WebSummaryService

    private var sourceCount: Int {
        store.webPageItems(for: webSummary.range).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    header
                    rangePicker
                    Spacer()
                    summaryButton
                }

                VStack(alignment: .leading, spacing: 10) {
                    header

                    HStack(spacing: 12) {
                        rangePicker
                        summaryButton
                    }
                }
            }

            HStack(spacing: 16) {
                Label(webSummary.statusText, systemImage: webSummary.isSummarizing ? "hourglass" : "info.circle")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Divider()
                    .frame(height: 16)

                Label("\(sourceCount) 条网页记录", systemImage: "globe")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let lastSummaryAt = webSummary.lastSummaryAt {
                    Text(DateFormatting.time.string(from: lastSummaryAt))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .font(.caption)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        Label("AI 网页摘要", systemImage: "globe.badge.chevron.backward")
            .font(.headline)
    }

    private var rangePicker: some View {
        Picker("范围", selection: $webSummary.range) {
            ForEach(WebSummaryRange.allCases) { range in
                Text(range.label).tag(range)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 130)
    }

    private var summaryButton: some View {
        Button {
            webSummary.summarize()
        } label: {
            Label(webSummary.isSummarizing ? "总结中" : "总结网页", systemImage: "wand.and.stars")
        }
        .disabled(webSummary.isSummarizing || sourceCount == 0)
    }
}
