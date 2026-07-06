import Foundation

final class DocumentImportIndexStore: ObservableObject {
    @Published private(set) var records: [DocumentImportRecord] = []

    private let database: SQLiteDatabase
    private let legacyFileURL: URL

    init(fileManager: FileManager = .default) {
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("WorkMemory", isDirectory: true)
        ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WorkMemory", isDirectory: true)

        self.legacyFileURL = supportURL.appendingPathComponent("document_index.json")
        self.database = try! SQLiteDatabase(fileManager: fileManager)

        migrateLegacyJSONIfNeeded(fileManager: fileManager)
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
