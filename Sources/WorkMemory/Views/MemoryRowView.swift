import SwiftUI

struct MemoryRowView: View {
    @EnvironmentObject private var store: MemoryStore
    let item: MemoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(item.category.label, systemImage: item.category.systemImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(item.category.tint)

                if let context = item.context {
                    Label(context.source.label, systemImage: context.source.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(DateFormatting.dateTime.string(from: item.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(item.title)
                .font(.headline)
                .lineLimit(2)

            Text(item.content)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(4)

            if let context = item.context {
                Label(context.summary, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            if !item.actionItems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(item.actionItems, id: \.self) { action in
                        Label(action, systemImage: "checklist")
                            .font(.callout)
                    }
                }
                .padding(.top, 2)
            }

            HStack {
                Toggle(isOn: Binding(
                    get: { store.isSelectedForSummary(item) },
                    set: { store.setSelectedForSummary(item, selected: $0) }
                )) {
                    Label("选入总结", systemImage: "checkmark.square")
                }
                .toggleStyle(.checkbox)
                .help("把这条记忆加入手动 AI 总结")

                Button {
                    store.select(item: item)
                } label: {
                    Label("查看全文", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderless)

                Menu {
                    ForEach(MemoryCategory.allCases) { category in
                        Button {
                            store.updateCategory(for: item, to: category)
                        } label: {
                            Label(category.label, systemImage: category.systemImage)
                        }
                    }
                } label: {
                    Label("改分类", systemImage: "tag")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)

                Spacer()

                Button(role: .destructive) {
                    store.delete(item)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除记录")
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator.opacity(0.35))
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            store.select(item: item)
        }
    }
}
