import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject private var store: MemoryStore
    @State private var projectName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("项目", systemImage: "folder")
                    .font(.headline)
                Spacer()
                TextField("新项目名称", text: $projectName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                    .onSubmit(addProject)
                Button(action: addProject) {
                    Label("新建", systemImage: "plus")
                }
                .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if store.projects.filter({ !$0.isArchived }).isEmpty {
                EmptyStateView(title: "还没有项目", message: "新建项目后，可把记忆和工作会话归到同一上下文。")
            } else {
                ForEach(store.projects.filter { !$0.isArchived }) { project in
                    projectSection(project)
                }
            }
        }
    }

    private func projectSection(_ project: MemoryProject) -> some View {
        let memories = store.items.filter { $0.projectID == project.id }
        let activities = store.activities.filter { $0.projectID == project.id }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(project.name).font(.title3.weight(.semibold))
                Text("\(memories.count) 条记忆 · \(activities.count) 个会话")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if !memories.isEmpty {
                MemoryListView(title: "项目记忆", items: Array(memories.prefix(12)))
            }
            if !activities.isEmpty {
                ForEach(activities.prefix(8)) { activity in
                    ProjectActivityRow(activity: activity)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func addProject() {
        if store.addProject(named: projectName) != nil { projectName = "" }
    }
}

private struct ProjectActivityRow: View {
    @EnvironmentObject private var store: MemoryStore
    let activity: ActivitySession

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: activity.source.systemImage)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.displayTitle).font(.callout.weight(.medium))
                Text("\(DateFormatting.time.string(from: activity.startedAt)) - \(DateFormatting.time.string(from: activity.endedAt)) · \(activity.eventCount) 次更新")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("提炼为记忆") { store.promoteActivity(activity) }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}
