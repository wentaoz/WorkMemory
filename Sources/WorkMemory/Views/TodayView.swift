import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: MemoryStore
    @EnvironmentObject private var actionStore: ActionItemStore

    private var todayMemories: [MemoryItem] { store.todayItems }
    private var todayActivities: [ActivitySession] { store.todayActivities }
    private var pinnedMemories: [MemoryItem] { store.items.filter(\.isPinned).prefix(5).map { $0 } }
    private var latestSummary: MemoryItem? {
        store.items.first { $0.category == .summary && Calendar.current.isDateInToday($0.createdAt) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            metrics
            if !pinnedMemories.isEmpty { focusSection }
            HStack(alignment: .top, spacing: 18) {
                timeline
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 16) {
                    actionSection
                    summarySection
                }
                .frame(width: 320, alignment: .topLeading)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Label("今日工作台", systemImage: "sun.max")
                    .font(.title3.weight(.semibold))
                Text("从活动中提炼记忆，再把记忆转成行动。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(DateFormatting.mediumDate.string(from: Date()))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var metrics: some View {
        HStack(spacing: 12) {
            TodayMetric(title: "工作会话", value: todayActivities.count, image: "clock")
            TodayMetric(title: "新记忆", value: todayMemories.count, image: "brain.head.profile")
            TodayMetric(title: "待推进", value: actionStore.openItems.count, image: "checklist")
            TodayMetric(title: "项目", value: store.projects.filter { !$0.isArchived }.count, image: "folder")
        }
    }

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("今日焦点").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(pinnedMemories) { item in
                        Button {
                            store.select(item: item)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Label(item.category.label, systemImage: item.category.systemImage)
                                    .font(.caption)
                                Text(item.title).font(.callout.weight(.medium)).lineLimit(2)
                            }
                            .frame(width: 210, alignment: .leading)
                            .padding(10)
                        }
                        .buttonStyle(.plain)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("工作会话").font(.headline)
                Spacer()
                Text("已聚合 \(todayActivities.reduce(0) { $0 + $1.eventCount }) 次采集")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if todayActivities.isEmpty {
                EmptyStateView(title: "今天还没有工作会话", message: "开启无感采集后，稳定停留的窗口和网页会自动聚合到这里。")
            } else {
                ForEach(todayActivities.prefix(12)) { activity in
                    TodayActivityRow(activity: activity)
                }
            }
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("待推进").font(.headline)
                Spacer()
                Text("\(actionStore.openItems.count)").foregroundStyle(.secondary)
            }
            if actionStore.openItems.isEmpty {
                Text("暂无待办，可从记忆中使用 AI 抽取。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(actionStore.openItems.prefix(6)) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Button { actionStore.toggleCompletion(item) } label: { Image(systemName: "circle") }
                            .buttonStyle(.borderless)
                        Text(item.title).font(.callout).lineLimit(2)
                    }
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近总结").font(.headline)
            if let latestSummary {
                Button { store.select(item: latestSummary) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(latestSummary.title).font(.callout.weight(.medium)).lineLimit(2)
                        Text(latestSummary.content).font(.caption).foregroundStyle(.secondary).lineLimit(5)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text("今天还没有总结。AI 总结会基于聚合后的会话生成。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TodayMetric: View {
    let title: String
    let value: Int
    let image: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: image).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text("\(value)").font(.title3.weight(.semibold))
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TodayActivityRow: View {
    @EnvironmentObject private var store: MemoryStore
    let activity: ActivitySession

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: activity.source.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.displayTitle).font(.callout.weight(.medium)).lineLimit(1)
                Text(activity.content).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text("\(DateFormatting.time.string(from: activity.startedAt)) - \(DateFormatting.time.string(from: activity.endedAt)) · \(activity.eventCount) 次更新")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Menu {
                Button("未归类") { store.assignActivity(activity, to: nil) }
                ForEach(store.projects.filter { !$0.isArchived }) { project in
                    Button(project.name) { store.assignActivity(activity, to: project.id) }
                }
            } label: {
                Image(systemName: "folder")
            }
            .menuStyle(.borderlessButton)
            Button {
                store.promoteActivity(activity)
            } label: {
                Image(systemName: "sparkles")
            }
            .buttonStyle(.borderless)
            .help("提炼为记忆")
        }
        .padding(11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
