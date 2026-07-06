import SwiftUI

struct DocumentImportView: View {
    @EnvironmentObject private var documentImport: DocumentImportService
    @EnvironmentObject private var documentIndex: DocumentImportIndexStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Label("本地文档导入", systemImage: "folder.badge.gearshape")
                    .font(.headline)

                Spacer()

                Toggle(isOn: $documentImport.autoImportEnabled) {
                    Label("自动扫描", systemImage: "arrow.triangle.2.circlepath")
                }
                .toggleStyle(.switch)

                Button {
                    documentImport.chooseFolder()
                } label: {
                    Label("选择文件夹", systemImage: "folder")
                }

                Button {
                    documentImport.scanNow()
                } label: {
                    Label(documentImport.isScanning ? "扫描中" : "立即扫描", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(documentImport.isScanning || documentImport.folderPath.isEmpty)
            }

            HStack(spacing: 16) {
                Label(displayFolderPath, systemImage: "folder")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Divider()
                    .frame(height: 16)

                Label(documentImport.statusText, systemImage: documentImport.isScanning ? "hourglass" : "info.circle")
                    .foregroundStyle(.secondary)

                if let lastScannedAt = documentImport.lastScannedAt {
                    Text(DateFormatting.time.string(from: lastScannedAt))
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption)

            if !documentIndex.recentRecords.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(documentIndex.recentRecords) { record in
                        HStack(spacing: 10) {
                            Image(systemName: icon(for: record))
                                .foregroundStyle(color(for: record.status))
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.fileName)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)

                                Text(record.message.isEmpty ? record.status.label : record.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(record.fileExtension.uppercased())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var displayFolderPath: String {
        documentImport.folderPath.isEmpty ? "尚未选择文件夹" : documentImport.folderPath
    }

    private func icon(for record: DocumentImportRecord) -> String {
        switch record.status {
        case .pending:
            return "hourglass"
        case .imported:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private func color(for status: DocumentImportStatus) -> Color {
        switch status {
        case .pending:
            return .secondary
        case .imported:
            return .green
        case .failed:
            return .orange
        }
    }
}
