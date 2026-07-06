import SwiftUI

struct AskMemoryView: View {
    @EnvironmentObject private var askMemory: AskMemoryService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Label("Ask Memory", systemImage: "bubble.left.and.text.bubble.right")
                    .font(.headline)

                Picker("范围", selection: $askMemory.scope) {
                    ForEach(MemoryQueryScope.allCases) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                Spacer()

                Button {
                    askMemory.ask()
                } label: {
                    Label(askMemory.isAsking ? "查询中" : "提问", systemImage: "arrow.up.circle")
                }
                .disabled(askMemory.isAsking || askMemory.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            TextField("例如：今天有哪些待办？这个项目最近有哪些风险？我上周关于模型 API 说过什么？", text: $askMemory.question)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    askMemory.ask()
                }

            HStack(spacing: 16) {
                Label(askMemory.statusText, systemImage: askMemory.isAsking ? "hourglass" : "info.circle")
                    .foregroundStyle(.secondary)

                if !askMemory.referencedItems.isEmpty {
                    Label("参考 \(askMemory.referencedItems.count) 条记录", systemImage: "quote.bubble")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            if !askMemory.answer.isEmpty {
                Text(askMemory.answer)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
