import AppKit
import SwiftUI

struct DatabaseErrorView: View {
    let failure: DatabaseOpenFailure
    let onRetry: () -> Void
    let onRestore: (URL) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Label("无法打开工作记忆数据库", systemImage: "exclamationmark.triangle.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.orange)

                Text(failure.message)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("数据库路径")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(failure.databaseURL.path)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }

                Text("应用不会因此退出。如果已经有另一个 WorkMemory 在运行，先退出那个实例再重试。也可以从自动备份恢复。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("重试打开", action: onRetry)
                        .keyboardShortcut(.defaultAction)

                    Button("在 Finder 中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([failure.databaseURL])
                    }

                    if let backup = failure.backups.first {
                        Button("恢复最近备份") {
                            onRestore(backup)
                        }
                    }
                }

                if failure.backups.count > 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("其他备份")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(failure.backups.prefix(5), id: \.path) { backup in
                            Button(backup.lastPathComponent) {
                                onRestore(backup)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 18)
        }
    }
}
