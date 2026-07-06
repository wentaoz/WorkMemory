import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MemoryDetailSheetView: View {
    let item: MemoryItem
    let onClose: () -> Void
    @State private var wordExportStatus: String?

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    metadata

                    if let wordExportStatus {
                        Label(wordExportStatus, systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(item.content)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !item.actionItems.isEmpty {
                        actionItems
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 560, idealHeight: 680)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.category.systemImage)
                .foregroundStyle(item.category.tint)
                .font(.title2)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Label(item.category.label, systemImage: "tag")

                    if let context = item.context {
                        Label(context.source.label, systemImage: context.source.systemImage)
                    }

                    Text(DateFormatting.dateTime.string(from: item.createdAt))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if canExportWord {
                Button {
                    exportWordDocument()
                } label: {
                    Label("导出 Word", systemImage: "doc.richtext")
                }
            }

            Button {
                copyContent()
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }

            Button("关闭", action: onClose)
                .keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder
    private var metadata: some View {
        if let context = item.context {
            VStack(alignment: .leading, spacing: 8) {
                Label(context.summary, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if let url = context.url,
                   let linkURL = URL(string: url),
                   ["http", "https"].contains(linkURL.scheme?.lowercased()) {
                    Link(destination: linkURL) {
                        Label(url, systemImage: "link")
                    }
                    .lineLimit(2)
                }
            }
            .font(.callout)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var actionItems: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("行动项")
                .font(.headline)

            ForEach(item.actionItems, id: \.self) { action in
                Label(action, systemImage: "checklist")
                    .font(.callout)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func copyContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.content, forType: .string)
    }

    private var canExportWord: Bool {
        item.category == .summary || item.context?.source == .aiSummary
    }

    private func exportWordDocument() {
        let panel = NSSavePanel()
        panel.title = "导出 AI 总结为 Word"
        panel.nameFieldStringValue = WordDocumentExportService.defaultFileName(for: item)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        if let docxType = UTType(filenameExtension: "docx") {
            panel.allowedContentTypes = [docxType]
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try WordDocumentExportService.export(item: item, to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            wordExportStatus = "已导出并打开文件夹：\(url.lastPathComponent)"
        } catch {
            wordExportStatus = error.localizedDescription
        }
    }
}
