import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: MemoryStore
    @Binding var selection: SidebarSelection

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("今日工作记忆", systemImage: "sun.max")
                    .tag(SidebarSelection.today)

                Label("全部记录", systemImage: "tray.full")
                    .tag(SidebarSelection.all)
            }

            Section("工作台") {
                Label("AI 总结", systemImage: "sparkles")
                    .tag(SidebarSelection.summaries)

                Label("Ask Memory", systemImage: "bubble.left.and.text.bubble.right")
                    .tag(SidebarSelection.askMemory)

                Label("行动项", systemImage: "checklist")
                    .tag(SidebarSelection.actions)

                Label("运行日志", systemImage: "list.bullet.rectangle")
                    .tag(SidebarSelection.logs)
            }

            Section("分类") {
                ForEach(MemoryCategory.allCases) { category in
                    HStack(spacing: 10) {
                        Image(systemName: category.systemImage)
                            .foregroundStyle(category.tint)
                            .frame(width: 16)

                        Text(category.label)

                        Spacer()

                        Text("\(store.count(for: category))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(SidebarSelection.category(category))
                }
            }

            Section {
                Label("设置", systemImage: "gearshape")
                    .tag(SidebarSelection.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("WorkMemory")
        .frame(minWidth: 220, idealWidth: 240)
    }
}
