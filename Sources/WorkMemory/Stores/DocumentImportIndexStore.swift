import Foundation

final class DocumentImportIndexStore: ObservableObject {
    @Published private(set) var records: [DocumentImportRecord] = []

    private var database: SQLiteDatabase
    private let legacyFileURL: URL

    init(fileManager: FileManager = .default, supportURL explicitSupportURL: URL? = nil) {
        let supportURL = explicitSupportURL ?? WorkMemoryDataLocation.supportURL(fileManager: fileManager)

        self.legacyFileURL = supportURL.appendingPathComponent("document_index.json")
        do {
            self.database = try SQLiteDatabase.openShared(fileManager: fileManager, supportURL: supportURL)
            migrateLegacyJSONIfNeeded(fileManager: fileManager)
            records = database.loadDocumentImportRecords()
        } catch {
            self.database = SQLiteDatabase.makeInMemoryFallback()
            AppLogStore.shared.error(
                "文档索引数据库打开失败：\(error.localizedDescription)",
                category: "数据库"
            )
        }
    }

    func reload(using database: SQLiteDatabase) {
        self.database = database
        migrateLegacyJSONIfNeeded(fileManager: .default)
        records = database.loadDocumentImportRecords()
    }

    var recentRecords: [DocumentImportRecord] {
        Array(records.sorted { ($0.lastProcessedAt ?? .distantPast) > ($1.lastProcessedAt ?? .distantPast) }.prefix(8))
    }

    func needsProcessing(_ candidate: DocumentImportRecord) -> Bool {
        guard let existing = records.first(where: { $0.path == candidate.path }) else {
            return true
        }

        return existing.fingerprint != candidate.fingerprint || existing.status == .failed
    }

    func mark(_ record: DocumentImportRecord, status: DocumentImportStatus, message: String) {
        var updated = record
        updated.status = status
        updated.message = message
        updated.lastProcessedAt = Date()

        if let index = records.firstIndex(where: { $0.path == updated.path }) {
            records[index] = updated
        } else {
            records.insert(updated, at: 0)
        }

        database.upsertDocumentImportRecord(updated)
    }

    private func migrateLegacyJSONIfNeeded(fileManager: FileManager) {
        guard database.loadDocumentImportRecords().isEmpty,
              fileManager.fileExists(atPath: legacyFileURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: legacyFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let legacyRecords = try decoder.decode([DocumentImportRecord].self, from: data)
            legacyRecords.forEach { database.upsertDocumentImportRecord($0) }
        } catch {
            assertionFailure("Failed to migrate legacy document index: \(error.localizedDescription)")
        }
    }
}
