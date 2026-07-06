import SwiftUI

struct GlobalDictationControlView: View {
    @EnvironmentObject private var globalDictation: GlobalDictationService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    globalDictation.toggleRecording()
                } label: {
                    Label(
                        globalDictation.isRecording ? "停止全局听写" : "开始全局听写",
                        systemImage: globalDictation.isRecording ? "stop.circle.fill" : "waveform"
                    )
                }
                .keyboardShortcut(" ", modifiers: [.option, .shift])

                Toggle(isOn: $globalDictation.pasteAfterDictation) {
                    Label("结束后粘贴", systemImage: "doc.on.clipboard")
                }
                .toggleStyle(.switch)

                Spacer()

                Button {
                    globalDictation.requestSpeechPermissions()
                } label: {
                    Label("语音权限", systemImage: "mic.badge.plus")
                }

                if globalDictation.pasteAfterDictation && !globalDictation.accessibilityTrusted {
                    Button {
                        globalDictation.requestAccessibilityPermission()
                    } label: {
                        Label("辅助功能", systemImage: "lock.open")
                    }

                    Button {
                        globalDictation.openAccessibilitySettings()
                    } label: {
                        Image(systemName: "gear")
                    }
                    .help("打开辅助功能设置")
                }
            }

            HStack(spacing: 16) {
                Label(globalDictation.statusText, systemImage: globalDictation.isRecording ? "record.circle.fill" : "mic")
                    .foregroundStyle(globalDictation.isRecording ? Color.red : Color.secondary)

                Divider()
                    .frame(height: 16)

                Label(globalDictation.targetContextText, systemImage: "target")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let lastSavedAt = globalDictation.lastSavedAt {
                    Text(DateFormatting.time.string(from: lastSavedAt))
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption)

            if !globalDictation.transcript.isEmpty {
                Text(globalDictation.transcript)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
