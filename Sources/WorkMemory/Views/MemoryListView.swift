import SwiftUI

struct MemoryListView: View {
    @EnvironmentObject private var store: MemoryStore
    let title: String
    let items: [MemoryItem]
    var showsLoadMore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title3.weight(.semibold))

                Spacer()

                Text("\(items.count) 条")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button {
                    store.selectForSummary(items: items)
                } label: {
                    Label("本页全选", systemImage: "checkmark.square")
                }
                .disabled(items.isEmpty)

                Button {
                    store.clearSummarySelection()
                } label: {
                    Label("清空已选", systemImage: "xmark.square")
                }
                .disabled(store.selectedForSummaryCount == 0)
            }

            if items.isEmpty {
                EmptyStateView(
                    title: "没有匹配记录",
                    message: "换一个分类或搜索词，或者先保存一条新的工作记忆。"
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(items) { item in
                        MemoryRowView(item: item)
                            .environmentObject(store)
                    }
                }

                if showsLoadMore && store.items.count < store.totalMemoryCount {
                    HStack {
                        Spacer()
                        Button {
                            store.loadMoreMemories()
                        } label: {
                            Label("加载更多", systemImage: "arrow.down.circle")
                        }
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}
