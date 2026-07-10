import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: MemoryStore
    @State private var selectedSidebarID = SidebarSelection.today.id

    private var selection: Binding<SidebarSelection> {
        Binding(
            get: { SidebarSelection.from(id: selectedSidebarID) },
            set: { selectedSidebarID = $0.id }
        )
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: selection)
                .environmentObject(store)
        } detail: {
            DetailView(selection: selection.wrappedValue)
                .environmentObject(store)
        }
        .onReceive(store.$todayViewRequest) { _ in
            selectedSidebarID = SidebarSelection.today.id
        }
    }
}
