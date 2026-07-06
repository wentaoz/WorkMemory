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
                items: filteredItems
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

        case .logs:
            LogsView()

        case .settings:
            SettingsView()
        }
    }
}
