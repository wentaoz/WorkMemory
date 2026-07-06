import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: MemoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("今日复盘", systemImage: "sparkles")
                    .font(.title3.weight(.semibold))

                Spacer()

                Text("\(store.todayItems.count) 条记录")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if store.todayItems.isEmpty {
                EmptyStateView(
                    title: "今天还没有记录",
                    message: "按 Option + Space 打开窗口，先把一句话丢进来。"
                )
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    SummaryMetricView(
                        title: "想法",
                        value: count(.idea),
                        image: "lightbulb"
                    )

                    SummaryMetricView(
                        title: "待办",
                        value: count(.task),
                        image: "checkmark.circle"
                    )

                    SummaryMetricView(
                        title: "问题",
                        value: count(.question),
                        image: "questionmark.circle"
                    )

                    SummaryMetricView(
                        title: "决策",
                        value: count(.decision),
                        image: "seal"
                    )
                }

                if !store.openActionItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("需要推进")
                            .font(.headline)

                        ForEach(store.openActionItems, id: \.self) { action in
                            Label(action, systemImage: "arrow.right.circle")
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func count(_ category: MemoryCategory) -> Int {
        store.todayItems.filter { $0.category == category }.count
    }
}

private struct SummaryMetricView: View {
    let title: String
    let value: Int
    let image: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: image)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(value)")
                    .font(.title2.weight(.semibold))
            }

            Spacer()
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
