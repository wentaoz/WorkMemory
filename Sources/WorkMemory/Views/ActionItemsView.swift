import SwiftUI

struct ActionItemsView: View {
    @EnvironmentObject private var actionStore: ActionItemStore
    @EnvironmentObject private var extractor: ActionItemExtractionService
    @State private var showCompleted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Label("行动项", systemImage: "checklist")
                    .font(.headline)

                Text("\(actionStore.openItems.count) 个未完成")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Toggle(isOn: $showCompleted) {
                    Label("显示已完成", systemImage: "checkmark.circle")
                }
                .toggleStyle(.switch)

                Menu {
                    Button("抽取今天") {
                        extractor.extractToday()
                    }

                    Button("抽取最近 7 天") {
                        extractor.extractLastSevenDays()
                    }
                } label: {
                    Label(extractor.isExtracting ? "抽取中" : "AI 抽取", systemImage: "wand.and.stars")
                }
                .disabled(extractor.isExtracting)
            }

            HStack(spacing: 16) {
                Label(extractor.statusText, systemImage: extractor.isExtracting ? "hourglass" : "info.circle")
                    .foregroundStyle(.secondary)

                if let lastExtractedAt = extractor.lastExtractedAt {
                    Text(DateFormatting.time.string(from: lastExtractedAt))
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption)

            let visibleItems = showCompleted ? actionStore.items : actionStore.openItems
            if visibleItems.isEmpty {
                EmptyStateView(
                    title: "还没有行动项",
                    message: "点击 AI 抽取，把今天或最近 7 天的记录变成可勾选任务。"
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(visibleItems) { item in
                        ActionItemRowView(item: item)
                            .environmentObject(actionStore)
                    }
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ActionItemRowView: View {
    @EnvironmentObject private var actionStore: ActionItemStore
    let item: WorkActionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    actionStore.toggleCompletion(item)
                } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.borderless)

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.callout.weight(.medium))
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)

                    HStack(spacing: 10) {
                        if !item.project.isEmpty {
                            Label(item.project, systemImage: "folder")
                        }

                        if !item.owner.isEmpty {
                            Label(item.owner, systemImage: "person")
                        }

                        if !item.dueDateText.isEmpty {
                            Label(item.dueDateText, systemImage: "calendar")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if !item.evidence.isEmpty {
                        Text(item.evidence)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }

                    if !item.sourceTitle.isEmpty {
                        Label(item.sourceTitle, systemImage: "link")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button(role: .destructive) {
                    actionStore.delete(item)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除行动项")
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
