import SwiftUI

struct ActionItemsView: View {
    @EnvironmentObject private var actionStore: ActionItemStore
    @EnvironmentObject private var extractor: ActionItemExtractionService
    @EnvironmentObject private var reminders: ReminderExportService
    @State private var showCompleted = false
    @State private var editingItem: WorkActionItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Label("行动项", systemImage: "checklist")
                    .font(.headline)
                Text("\(actionStore.openItems.count) 个未完成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("显示已完成", isOn: $showCompleted)
                    .toggleStyle(.switch)
                Button {
                    editingItem = WorkActionItem(title: "")
                } label: {
                    Label("新建", systemImage: "plus")
                }
                extractionMenu
            }

            HStack(spacing: 16) {
                Label(extractor.statusText, systemImage: extractor.isExtracting ? "hourglass" : "info.circle")
                if reminders.statusText != "尚未同步提醒事项" {
                    Label(reminders.statusText, systemImage: "bell")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            let visibleItems = showCompleted ? actionStore.items : actionStore.items.filter { $0.status != .completed }
            if visibleItems.isEmpty {
                EmptyStateView(
                    title: "还没有行动项",
                    message: "新建行动项，或从今天和最近 7 天的记忆中提取。"
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(visibleItems) { item in
                        ActionItemRowView(item: item, onEdit: { editingItem = item })
                    }
                }
            }
        }
        .sheet(item: $editingItem) { item in
            ActionItemEditorView(item: item) { updated in
                if actionStore.items.contains(where: { $0.id == updated.id }) {
                    actionStore.update(updated)
                } else {
                    actionStore.add(updated)
                }
                editingItem = nil
            } onCancel: {
                editingItem = nil
            }
        }
    }

    private var extractionMenu: some View {
        Menu {
            Button("抽取今天", action: extractor.extractToday)
            Button("抽取最近 7 天", action: extractor.extractLastSevenDays)
        } label: {
            Label(extractor.isExtracting ? "抽取中" : "AI 抽取", systemImage: "wand.and.stars")
        }
        .disabled(extractor.isExtracting)
    }
}

private struct ActionItemRowView: View {
    @EnvironmentObject private var actionStore: ActionItemStore
    @EnvironmentObject private var reminders: ReminderExportService
    let item: WorkActionItem
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { actionStore.toggleCompletion(item) } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.callout.weight(.medium))
                        .strikethrough(item.isCompleted)
                    priorityLabel
                    if item.status == .deferred {
                        Label("稍后", systemImage: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                metadata
                if !item.evidence.isEmpty {
                    Text(item.evidence)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            Button(action: onEdit) { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
                .help("编辑行动项")
            Button {
                Task {
                    if let identifier = try? await reminders.export(item) {
                        actionStore.setReminderIdentifier(identifier, for: item)
                    }
                }
            } label: {
                Image(systemName: item.reminderIdentifier == nil ? "bell.badge" : "bell.fill")
            }
            .buttonStyle(.borderless)
            .disabled(reminders.isExporting)
            .help(item.reminderIdentifier == nil ? "加入提醒事项" : "更新提醒事项")
            Button { actionStore.deferAction(item) } label: { Image(systemName: "clock.arrow.circlepath") }
                .buttonStyle(.borderless)
                .disabled(item.isCompleted)
                .help("稍后处理")
            Button(role: .destructive) { actionStore.delete(item) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("删除行动项")
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var priorityLabel: some View {
        if item.priority != .normal {
            Text(item.priority.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(item.priority.color)
        }
    }

    private var metadata: some View {
        HStack(spacing: 10) {
            if !item.project.isEmpty { Label(item.project, systemImage: "folder") }
            if !item.owner.isEmpty { Label(item.owner, systemImage: "person") }
            if let dueDate = item.dueDate {
                Label(DateFormatting.mediumDate.string(from: dueDate), systemImage: "calendar")
                    .foregroundStyle(dueDate < Date() && !item.isCompleted ? .red : .secondary)
            } else if !item.dueDateText.isEmpty {
                Label(item.dueDateText, systemImage: "calendar")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct ActionItemEditorView: View {
    @State var draft: WorkActionItem
    @State private var hasDueDate: Bool
    let onSave: (WorkActionItem) -> Void
    let onCancel: () -> Void

    init(item: WorkActionItem, onSave: @escaping (WorkActionItem) -> Void, onCancel: @escaping () -> Void) {
        _draft = State(initialValue: item)
        _hasDueDate = State(initialValue: item.dueDate != nil)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.title.isEmpty ? "新建行动项" : "编辑行动项")
                .font(.title3.weight(.semibold))
            Form {
                TextField("行动项", text: $draft.title)
                TextField("项目", text: $draft.project)
                TextField("负责人", text: $draft.owner)
                Picker("优先级", selection: $draft.priority) {
                    ForEach(WorkActionPriority.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("状态", selection: $draft.status) {
                    Text("待处理").tag(WorkActionStatus.open)
                    Text("稍后").tag(WorkActionStatus.deferred)
                    Text("已完成").tag(WorkActionStatus.completed)
                }
                .pickerStyle(.segmented)
                Toggle("设置截止时间", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("截止时间", selection: Binding(
                        get: { draft.dueDate ?? Date() },
                        set: { draft.dueDate = $0 }
                    ))
                }
                TextField("依据或备注", text: $draft.evidence, axis: .vertical)
                    .lineLimit(3...6)
            }
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    if !hasDueDate { draft.dueDate = nil }
                    onSave(draft)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

private extension WorkActionPriority {
    var label: String {
        switch self {
        case .low: return "低"
        case .normal: return "普通"
        case .high: return "高"
        case .urgent: return "紧急"
        }
    }

    var color: Color {
        switch self {
        case .low: return .secondary
        case .normal: return .blue
        case .high: return .orange
        case .urgent: return .red
        }
    }
}
