import AppKit
import Foundation

@MainActor
final class DocumentImportService: ObservableObject {
    @Published var folderPath: String {
        didSet {
            UserDefaults.standard.set(folderPath, forKey: Self.folderPathKey)
        }
    }

    @Published var autoImportEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoImportEnabled, forKey: Self.autoImportEnabledKey)
            autoImportEnabled ? startTimer() : stopTimer()
        }
    }

    @Published private(set) var isScanning = false
    @Published private(set) var statusText = "文档导入未运行"
    @Published private(set) var lastScannedAt: Date?

    private static let folderPathKey = "documentImport.folderPath"
    private static let autoImportEnabledKey = "documentImport.autoImportEnabled"

    private weak var memoryStore: MemoryStore?
    private weak var indexStore: DocumentImportIndexStore?
    private var settings: DeepSeekSettings?
    private let extractor = DocumentTextExtractor()
    private let client = DeepSeekClient()
    private var timer: Timer?
    private let scanInterval: TimeInterval = 180
    private let maxFilesPerScan = 12

    init() {
        folderPath = UserDefaults.standard.string(forKey: Self.folderPathKey) ?? ""
        autoImportEnabled = UserDefaults.standard.object(forKey: Self.autoImportEnabledKey) as? Bool ?? false
    }

    func configure(
        memoryStore: MemoryStore,
        indexStore: DocumentImportIndexStore,
        settings: DeepSeekSettings
    ) {
        self.memoryStore = memoryStore
        self.indexStore = indexStore
        self.settings = settings

        if autoImportEnabled {
            startTimer()
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择文件夹"

        if panel.runModal() == .OK, let url = panel.url {
            folderPath = url.path
            statusText = "已选择：\(url.lastPathComponent)"
        }
    }

    func scanNow() {
        Task {
            await scanFolder()
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: scanInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.scanFolder()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func scanFolder() async {
        guard !isScanning else { return }
        guard let memoryStore, let indexStore, let settings else { return }

        let trimmedPath = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            statusText = "请先选择文件夹"
            AppLogStore.shared.warning("文档扫描已取消：未选择文件夹。", category: "文档导入")
            return
        }

        let folderURL = URL(fileURLWithPath: trimmedPath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: folderURL.path) else {
            statusText = "文件夹不存在"
            AppLogStore.shared.error("文档扫描失败：文件夹不存在 \(trimmedPath)", category: "文档导入")
            return
        }

        isScanning = true
        statusText = "正在扫描文档..."

        do {
            let candidates = try discoverCandidates(in: folderURL)
                .filter { indexStore.needsProcessing($0) }
                .prefix(maxFilesPerScan)

            guard !candidates.isEmpty else {
                lastScannedAt = Date()
                statusText = "没有需要导入的新文档"
                AppLogStore.shared.info("文档扫描完成：没有需要导入的新文档。", category: "文档导入")
                isScanning = false
                return
            }

            var importedCount = 0
            var failedCount = 0

            for candidate in candidates {
                do {
                    indexStore.mark(candidate, status: .pending, message: "正在提取文本")
                    let extracted = try extractor.extract(from: URL(fileURLWithPath: candidate.path))

                    indexStore.mark(candidate, status: .pending, message: "正在调用模型摘要")
                    let summary = try await client.summarizeDocument(
                        fileName: candidate.fileName,
                        filePath: candidate.path,
                        modifiedAt: candidate.modifiedAt,
                        extractedText: extracted.text,
                        configuration: DeepSeekClient.Configuration(
                            apiKey: settings.apiKey,
                            baseURL: settings.baseURL,
                            model: settings.model
                        )
                    )

                    memoryStore.addDocumentSummary(
                        content: summary,
                        fileName: candidate.fileName,
                        filePath: candidate.path,
                        modifiedAt: candidate.modifiedAt
                    )
                    indexStore.mark(candidate, status: .imported, message: "\(extracted.format.uppercased()) 摘要已加入今日记忆")
                    importedCount += 1
                } catch {
                    indexStore.mark(candidate, status: .failed, message: error.localizedDescription)
                    AppLogStore.shared.error(
                        """
                        文档导入失败
                        文件：\(candidate.fileName)
                        路径：\(candidate.path)
                        错误：\(error.localizedDescription)
                        """,
                        category: "文档导入"
                    )
                    failedCount += 1
                }
            }

            lastScannedAt = Date()
            statusText = "文档扫描完成：导入 \(importedCount)，失败 \(failedCount)"
            AppLogStore.shared.info(
                "文档扫描完成：导入 \(importedCount)，失败 \(failedCount)，扫描目录 \(folderURL.path)。",
                category: "文档导入"
            )
        } catch {
            statusText = error.localizedDescription
            AppLogStore.shared.error("文档扫描失败：\(error.localizedDescription)", category: "文档导入")
        }

        isScanning = false
    }

    private func discoverCandidates(in folderURL: URL) throws -> [DocumentImportRecord] {
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var records: [DocumentImportRecord] = []

        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard extractor.supportedExtensions.contains(ext) else { continue }

            let values = try fileURL.resourceValues(forKeys: Set(resourceKeys))
            guard values.isRegularFile == true else { continue }

            let modifiedAt = values.contentModificationDate ?? .distantPast
            let size = UInt64(values.fileSize ?? 0)
            guard size > 0 else { continue }

            records.append(
                DocumentImportRecord(
                    path: fileURL.path,
                    fileName: fileURL.lastPathComponent,
                    fileExtension: ext,
                    modifiedAt: modifiedAt,
                    size: size,
                    lastProcessedAt: nil,
                    status: .pending,
                    message: ""
                )
            )
        }

        return records.sorted { $0.modifiedAt > $1.modifiedAt }
    }
}
