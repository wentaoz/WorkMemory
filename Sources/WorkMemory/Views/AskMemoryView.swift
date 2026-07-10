import SwiftUI

struct AskMemoryView: View {
    @EnvironmentObject private var askMemory: AskMemoryService
    @EnvironmentObject private var store: MemoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if askMemory.turns.isEmpty { suggestions }
            ForEach(askMemory.turns) { turn in
                turnView(turn)
            }
            composer
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label("Ask Memory", systemImage: "bubble.left.and.text.bubble.right")
                .font(.headline)
            Picker("范围", selection: $askMemory.scope) {
                ForEach(MemoryQueryScope.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            Picker("项目", selection: $askMemory.selectedProjectID) {
                Text("全部项目").tag(Optional<UUID>.none)
                ForEach(store.projects.filter { !$0.isArchived }) { project in
                    Text(project.name).tag(Optional(project.id))
                }
            }
            .frame(width: 160)
            Spacer()
            Button {
                askMemory.clearConversation()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .help("新对话")
            .disabled(askMemory.turns.isEmpty)
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("可以这样问").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                suggestion("今天主要推进了什么？")
                suggestion("最近有哪些未解决的风险？")
                suggestion("我对当前项目做过哪些决定？")
            }
        }
    }

    private func suggestion(_ text: String) -> some View {
        Button(text) {
            askMemory.question = text
            askMemory.ask()
        }
        .buttonStyle(.bordered)
    }

    private func turnView(_ turn: AskMemoryTurn) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "person.crop.circle")
                Text(turn.question).font(.callout.weight(.medium))
            }
            Text(turn.answer)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !turn.citations.isEmpty {
                Divider()
                Text("引用证据").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(turn.citations) { citation in
                    Button {
                        store.select(reference: citation.reference)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Text(citation.marker).font(.caption.monospacedDigit())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(citation.title).font(.caption.weight(.medium)).lineLimit(1)
                                Text([citation.locator, citation.excerpt].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("询问记忆、文档、项目或行动项", text: $askMemory.question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(askMemory.ask)
                Button {
                    askMemory.ask()
                } label: {
                    Label(askMemory.isAsking ? "查询中" : "提问", systemImage: "arrow.up.circle")
                }
                .disabled(askMemory.isAsking || askMemory.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Label(askMemory.statusText, systemImage: askMemory.isAsking ? "hourglass" : "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
