import Foundation
import SQLite3

final class SQLiteDatabase {
    private let db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) throws {
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("WorkMemory", isDirectory: true)
        ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WorkMemory", isDirectory: true)

        try fileManager.createDirectory(at: supportURL, withIntermediateDirectories: true)
        let dbURL = supportURL.appendingPathComponent("workmemory.sqlite")

        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            throw SQLiteStoreError.openFailed
        }

        self.db = db
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        try createSchema()
    }

    deinit {
        sqlite3_close(db)
    }

    func loadMemories() -> [MemoryItem] {
        query(
            """
            SELECT id, title, content, category, action_items_json, created_at,
                   context_source, context_app_name, context_bundle_id,
                   context_window_title, context_page_title, context_url
            FROM memories
            ORDER BY created_at DESC
            """
        ) { statement in
            let id = UUID(uuidString: columnText(statement, 0) ?? "") ?? UUID()
            let category = MemoryCategory(rawValue: columnText(statement, 3) ?? "") ?? .note
            let actionItems = decodeStringArray(columnText(statement, 4), decoder: decoder)
            let context = decodeContext(statement: statement, startIndex: 6)

            return MemoryItem(
                id: id,
                title: columnText(statement, 1) ?? "",
                content: columnText(statement, 2) ?? "",
                category: category,
                actionItems: actionItems,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                context: context
            )
        }
    }

    func upsertMemory(_ item: MemoryItem) {
        let actionItems = (try? String(data: encoder.encode(item.actionItems), encoding: .utf8)) ?? "[]"
        let context = item.context

        execute(
            """
            INSERT OR REPLACE INTO memories (
                id, title, content, category, action_items_json, created_at,
                context_source, context_app_name, context_bundle_id,
                context_window_title, context_page_title, context_url
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(item.id.uuidString),
                .text(item.title),
                .text(item.content),
                .text(item.category.rawValue),
                .text(actionItems),
                .double(item.createdAt.timeIntervalSince1970),
                .text(context?.source.rawValue),
                .text(context?.appName),
                .text(context?.bundleIdentifier),
                .text(context?.windowTitle),
                .text(context?.pageTitle),
                .text(context?.url)
            ]
        )

        execute(
            """
            INSERT OR REPLACE INTO memory_fts (
                id, title, content, category, context_summary, action_items
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            [
                .text(item.id.uuidString),
                .text(item.title),
                .text(item.content),
                .text(item.category.label),
                .text(item.context?.summary ?? ""),
                .text(item.actionItems.joined(separator: "\n"))
            ]
        )
    }

    func deleteMemory(id: UUID) {
        execute("DELETE FROM memories WHERE id = ?", [.text(id.uuidString)])
        execute("DELETE FROM memory_fts WHERE id = ?", [.text(id.uuidString)])
    }

    func searchMemoryIDs(query rawQuery: String) -> Set<UUID> {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        var ids = Set<UUID>()
        let ftsQuery = query
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            .joined(separator: " OR ")

        if !ftsQuery.isEmpty {
            ids.formUnion(
                self.query("SELECT id FROM memory_fts WHERE memory_fts MATCH ?", [.text(ftsQuery)]) { statement in
                    columnText(statement, 0).flatMap(UUID.init(uuidString:))
                }
                .compactMap { $0 }
            )
        }

        let likeQuery = "%\(query)%"
        ids.formUnion(
            self.query(
                """
                SELECT id
                FROM memories
                WHERE title LIKE ?
                   OR content LIKE ?
                   OR category LIKE ?
                   OR action_items_json LIKE ?
                   OR context_app_name LIKE ?
                   OR context_window_title LIKE ?
                   OR context_page_title LIKE ?
                   OR context_url LIKE ?
                """,
                Array(repeating: .text(likeQuery), count: 8)
            ) { statement in
                columnText(statement, 0).flatMap(UUID.init(uuidString:))
            }
            .compactMap { $0 }
        )

        return ids
    }

    func loadActionItems() -> [WorkActionItem] {
        query(
            """
            SELECT id, title, project, owner, due_date_text, evidence,
                   source_memory_id, source_title, created_at, is_completed
            FROM action_items
            ORDER BY created_at DESC
            """
        ) { statement in
            WorkActionItem(
                id: UUID(uuidString: columnText(statement, 0) ?? "") ?? UUID(),
                title: columnText(statement, 1) ?? "",
                project: columnText(statement, 2) ?? "",
                owner: columnText(statement, 3) ?? "",
                dueDateText: columnText(statement, 4) ?? "",
                evidence: columnText(statement, 5) ?? "",
                sourceMemoryID: columnText(statement, 6).flatMap(UUID.init(uuidString:)),
                sourceTitle: columnText(statement, 7) ?? "",
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 8)),
                isCompleted: sqlite3_column_int(statement, 9) == 1
            )
        }
    }

    func upsertActionItem(_ item: WorkActionItem) {
        execute(
            """
            INSERT OR REPLACE INTO action_items (
                id, title, project, owner, due_date_text, evidence,
                source_memory_id, source_title, created_at, is_completed
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(item.id.uuidString),
                .text(item.title),
                .text(item.project),
                .text(item.owner),
                .text(item.dueDateText),
                .text(item.evidence),
                .text(item.sourceMemoryID?.uuidString),
                .text(item.sourceTitle),
                .double(item.createdAt.timeIntervalSince1970),
                .int(item.isCompleted ? 1 : 0)
            ]
        )
    }

    func deleteActionItem(id: UUID) {
        execute("DELETE FROM action_items WHERE id = ?", [.text(id.uuidString)])
    }

    func loadDocumentImportRecords() -> [DocumentImportRecord] {
        query(
            """
            SELECT path, file_name, file_extension, modified_at, size,
                   last_processed_at, status, message
            FROM document_imports
            ORDER BY COALESCE(last_processed_at, 0) DESC
            """
        ) { statement in
            let lastProcessedValue = sqlite3_column_type(statement, 5) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))

            return DocumentImportRecord(
                path: columnText(statement, 0) ?? "",
                fileName: columnText(statement, 1) ?? "",
                fileExtension: columnText(statement, 2) ?? "",
                modifiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                size: UInt64(sqlite3_column_int64(statement, 4)),
                lastProcessedAt: lastProcessedValue,
                status: DocumentImportStatus(rawValue: columnText(statement, 6) ?? "") ?? .pending,
                message: columnText(statement, 7) ?? ""
            )
        }
    }

    func upsertDocumentImportRecord(_ record: DocumentImportRecord) {
        execute(
            """
            INSERT OR REPLACE INTO document_imports (
                path, file_name, file_extension, modified_at, size,
                last_processed_at, status, message
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(record.path),
                .text(record.fileName),
                .text(record.fileExtension),
                .double(record.modifiedAt.timeIntervalSince1970),
                .int64(Int64(record.size)),
                .double(record.lastProcessedAt?.timeIntervalSince1970),
                .text(record.status.rawValue),
                .text(record.message)
            ]
        )
    }

    private func createSchema() throws {
        try executeThrowing("PRAGMA journal_mode = WAL")
        try executeThrowing(
            """
            CREATE TABLE IF NOT EXISTS memories (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                category TEXT NOT NULL,
                action_items_json TEXT NOT NULL,
                created_at REAL NOT NULL,
                context_source TEXT,
                context_app_name TEXT,
                context_bundle_id TEXT,
                context_window_title TEXT,
                context_page_title TEXT,
                context_url TEXT
            )
            """
        )
        try executeThrowing("CREATE INDEX IF NOT EXISTS idx_memories_created_at ON memories(created_at)")
        try executeThrowing("CREATE INDEX IF NOT EXISTS idx_memories_category ON memories(category)")
        try executeThrowing(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS memory_fts USING fts5(
                id UNINDEXED,
                title,
                content,
                category,
                context_summary,
                action_items
            )
            """
        )
        try executeThrowing(
            """
            CREATE TABLE IF NOT EXISTS action_items (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                project TEXT NOT NULL,
                owner TEXT NOT NULL,
                due_date_text TEXT NOT NULL,
                evidence TEXT NOT NULL,
                source_memory_id TEXT,
                source_title TEXT NOT NULL,
                created_at REAL NOT NULL,
                is_completed INTEGER NOT NULL
            )
            """
        )
        try executeThrowing("CREATE INDEX IF NOT EXISTS idx_action_items_completed ON action_items(is_completed)")
        try executeThrowing(
            """
            CREATE TABLE IF NOT EXISTS document_imports (
                path TEXT PRIMARY KEY,
                file_name TEXT NOT NULL,
                file_extension TEXT NOT NULL,
                modified_at REAL NOT NULL,
                size INTEGER NOT NULL,
                last_processed_at REAL,
                status TEXT NOT NULL,
                message TEXT NOT NULL
            )
            """
        )
    }

    private func execute(_ sql: String, _ values: [SQLiteValue] = []) {
        try? executeThrowing(sql, values)
    }

    private func executeThrowing(_ sql: String, _ values: [SQLiteValue] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.prepareFailed(message)
        }
        defer { sqlite3_finalize(statement) }

        bind(values, to: statement)

        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw SQLiteStoreError.stepFailed(message)
        }
    }

    private func query<T>(_ sql: String, _ values: [SQLiteValue] = [], map: (OpaquePointer?) -> T) -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        bind(values, to: statement)

        var result: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(map(statement))
        }
        return result
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer?) {
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .text(let string):
                guard let string else {
                    sqlite3_bind_null(statement, position)
                    continue
                }
                sqlite3_bind_text(statement, position, string, -1, SQLiteDatabase.transient)
            case .double(let double):
                guard let double else {
                    sqlite3_bind_null(statement, position)
                    continue
                }
                sqlite3_bind_double(statement, position, double)
            case .int(let int):
                sqlite3_bind_int(statement, position, Int32(int))
            case .int64(let int):
                sqlite3_bind_int64(statement, position, int)
            }
        }
    }

    private var message: String {
        guard let message = sqlite3_errmsg(db) else { return "Unknown SQLite error" }
        return String(cString: message)
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

enum SQLiteValue {
    case text(String?)
    case double(Double?)
    case int(Int)
    case int64(Int64)
}

enum SQLiteStoreError: LocalizedError {
    case openFailed
    case prepareFailed(String)
    case stepFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed:
            return "无法打开 SQLite 数据库"
        case .prepareFailed(let message):
            return "SQLite prepare failed: \(message)"
        case .stepFailed(let message):
            return "SQLite step failed: \(message)"
        }
    }
}

private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL,
          let text = sqlite3_column_text(statement, index) else {
        return nil
    }

    return String(cString: text)
}

private func decodeStringArray(_ rawValue: String?, decoder: JSONDecoder) -> [String] {
    guard let rawValue,
          let data = rawValue.data(using: .utf8),
          let items = try? decoder.decode([String].self, from: data) else {
        return []
    }

    return items
}

private func decodeContext(statement: OpaquePointer?, startIndex: Int32) -> CapturedContext? {
    guard let sourceRawValue = columnText(statement, startIndex),
          let source = MemorySource(rawValue: sourceRawValue) else {
        return nil
    }

    return CapturedContext(
        source: source,
        appName: columnText(statement, startIndex + 1),
        bundleIdentifier: columnText(statement, startIndex + 2),
        windowTitle: columnText(statement, startIndex + 3),
        pageTitle: columnText(statement, startIndex + 4),
        url: columnText(statement, startIndex + 5)
    )
}
