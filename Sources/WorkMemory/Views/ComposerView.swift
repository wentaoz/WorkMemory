import SwiftUI

struct ComposerView: View {
    @EnvironmentObject private var store: MemoryStore
    @StateObject private var transcriber = SpeechTranscriber()
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("快速捕捉", systemImage: "square.and.pencil")
                    .font(.headline)

                Spacer()

                Button {
                    transcriber.toggleRecording()
                } label: {
                    Image(systemName: transcriber.isRecording ? "stop.circle.fill" : "mic")
                }
                .buttonStyle(.borderless)
                .help(transcriber.isRecording ? "停止语音输入" : "开始语音输入")
                .disabled(!transcriber.canRecord)

                Button {
                    saveDraft()
                } label: {
                    Label("保存", systemImage: "tray.and.arrow.down")
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            TextEditor(text: $draft)
                .focused($isFocused)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 92, maxHeight: 132)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("输入一句想法、粘贴一段聊天，或点击麦克风开始说。")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

            if let statusMessage = transcriber.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onReceive(store.$composerFocusRequest) { _ in
            isFocused = true
        }
        .onChange(of: transcriber.transcript) { transcript in
            guard !transcript.isEmpty else { return }
            draft = transcript
        }
    }

    private func saveDraft() {
        store.addMemory(content: draft)
        draft = ""
        transcriber.resetTranscript()
        isFocused = true
    }
}
