import SwiftUI

struct DetailView: View {
    @EnvironmentObject private var store: MemoryStore
    let selection: SidebarSelection
    @State private var allRecordsDatePreset: MemoryDateFilterPreset = .all
    @State private var allRecordsCustomStartDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var allRecordsCustomEndDate = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(selection.title)
        .searchable(text: $store.searchText, prompt: "搜索记录、任务、问题")
        .sheet(
            isPresented: Binding(
                get: { store.selectedItem != nil },
                set: { isPresented in
                    if !isPresented {
                        store.clearSelection()
                    }
                }
            )
        ) {
            if let item = store.selectedItem {
                MemoryDetailSheetView(item: item) {
                    store.clearSelection()
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { store.selectedActivity != nil },
                set: { if !$0 { store.clearSelection() } }
            )
        ) {
            if let activity = store.selectedActivity {
                ActivityDetailSheetView(activity: activity) {
                    store.clearSelection()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .today:
            ComposerView()
                .environmentObject(store)

            TodayView()
                .environmentObject(store)

            MemoryListView(
                title: selection.title,
                items: store.items(for: selection)
            )
            .environmentObject(store)

        case .all:
            let allItems = store.items(for: selection)
            let filteredItems = allItems.filter { item in
                allRecordsDatePreset.contains(
                    item.createdAt,
                    customStartDate: allRecordsCustomStartDate,
                    customEndDate: allRecordsCustomEndDate
                )
            }

            MemoryDateFilterView(
                preset: $allRecordsDatePreset,
                customStartDate: $allRecordsCustomStartDate,
                customEndDate: $allRecordsCustomEndDate,
                filteredCount: filteredItems.count,
                totalCount: allItems.count
            )

            MemoryListView(
                title: selection.title,
                items: filteredItems,
                showsLoadMore: true
            )
            .environmentObject(store)

        case .category:
            MemoryListView(
                title: selection.title,
                items: store.items(for: selection)
            )
            .environmentObject(store)

        case .summaries:
            SummaryWorkspaceView()

        case .askMemory:
            AskMemoryView()

        case .actions:
            ActionItemsView()

        case .projects:
            ProjectsView()

        case .logs:
            LogsView()

        case .settings:
            SettingsView()
        }
    }
}

private struct ActivityDetailSheetView: View {
    @EnvironmentObject private var store: MemoryStore
    let activity: ActivitySession
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(activity.displayTitle, systemImage: activity.source.systemImage)
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("提炼为记忆") {
                    store.promoteActivity(activity)
                    onClose()
                }
                Button("关闭", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 12) {
                Text("\(DateFormatting.dateTime.string(from: activity.startedAt)) - \(DateFormatting.dateTime.string(from: activity.endedAt))")
                Text("\(activity.eventCount) 次更新")
                if activity.isArchived { Text("已归档") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Divider()
            ScrollView {
                Text(activity.content)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 520)
    }
}
