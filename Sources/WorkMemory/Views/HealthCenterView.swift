import AppKit
import SwiftUI

struct HealthCenterView: View {
    @EnvironmentObject private var store: MemoryStore
    @EnvironmentObject private var capture: PassiveCaptureMonitor
    @EnvironmentObject private var documentImport: DocumentImportService
    @EnvironmentObject private var documentIndex: DocumentImportIndexStore
    @EnvironmentObject private var settings: DeepSeekSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("数据健康", systemImage: "heart.text.square")
                    .font(.headline)
                Spacer()
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: store.databasePath)])
                } label: {
                    Label("显示数据库", systemImage: "folder")
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 9) {
                healthRow("数据库", value: ByteCountFormatter.string(fromByteCount: store.databaseSize, countStyle: .file), image: "externaldrive")
                healthRow("数据结构", value: "v\(store.databaseSchemaVersion)", image: "cylinder")
                healthRow("记忆", value: "\(store.totalMemoryCount) 条", image: "brain.head.profile")
                healthRow("工作会话", value: "\(store.totalActivityCount) 个活跃 · \(store.archivedActivityCount) 个归档", image: "clock")
                healthRow("无感记录", value: capture.statusText, image: capture.isEnabled ? "record.circle.fill" : "record.circle")
                healthRow("模型", value: settings.apiKey.isEmpty ? "未配置" : "\(settings.model) 已配置", image: "sparkles")
                healthRow("文档索引", value: documentStatus, image: "doc.text.magnifyingglass")
            }
            .font(.caption)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var documentStatus: String {
        let imported = documentIndex.records.filter { $0.status == .imported }.count
        let failed = documentIndex.records.filter { $0.status == .failed }.count
        if documentImport.isScanning { return "扫描中" }
        return "\(imported) 个已导入 · \(failed) 个失败"
    }

    private func healthRow(_ label: String, value: String, image: String) -> some View {
        GridRow {
            Label(label, systemImage: image)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }
}
