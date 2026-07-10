import Foundation
import SQLite3

extension SQLiteDatabase {
    static let currentSchemaVersion = 2

    func migrateToCurrentSchema(fileManager: FileManager, supportURL: URL) throws {
        let version = query("PRAGMA user_version") { statement in
            Int(sqlite3_column_int(statement, 0))
        }.first ?? 0
        if version >= Self.currentSchemaVersion {
            try executeThrowing("CREATE INDEX IF NOT EXISTS idx_memories_context_source ON memories(context_source)")
            try executeThrowing("BEGIN IMMEDIATE TRANSACTION")
            do {
                try migrateLegacyPassiveMemories()
                try executeThrowing("COMMIT")
            } catch {
                try? executeThrowing("ROLLBACK")
                throw error
            }
            return
        }

        let existingCount = query("SELECT COUNT(*) FROM memories") { statement in
            Int(sqlite3_column_int64(statement, 0))
        }.first ?? 0
        if existingCount > 0 {
            try backupBeforeMigration(fileManager: fileManager, supportURL: supportURL)
        }

        try executeThrowing("BEGIN IMMEDIATE TRANSACTION")
        do {
            try createV2Schema()
            try addV2Columns()
            try migrateLegacyPassiveMemories()
            try executeThrowing("PRAGMA user_version = \(Self.currentSchemaVersion)")
            try executeThrowing("COMMIT")
        } catch {
            try? executeThrowing("ROLLBACK")
            throw error
        }
    }

    private func backupBeforeMigration(fileManager: FileManager, supportURL: URL) throws {
        _ = sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_FULL, nil, nil)
        let sourceURL = supportURL.appendingPathComponent("workmemory.sqlite")
        guard fileManager.fileExists(atPath: sourceURL.path) else { return }

        let backupDirectory = supportURL.appendingPathComponent("Backups", isDirectory: true)
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupURL = backupDirectory.appendingPathComponent(
            "pre-v1.1-\(formatter.string(from: Date())).sqlite"
        )
        if !fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.copyItem(at: sourceURL, to: backupURL)
        }
    }

    private func createV2Schema() throws {
        try executeThrowing(
            """
            CREATE TABLE IF NOT EXISTS activities (
                id TEXT PRIMARY KEY,
                source TEXT NOT NULL,
                context_key TEXT NOT NULL,
                content TEXT NOT NULL,
                context_app_name TEXT,
                context_bundle_id TEXT,
                context_window_title TEXT,
                context_page_title TEXT,
                context_url TEXT,
                started_at REAL NOT NULL,
                ended_at REAL NOT NULL,
                event_count INTEGER NOT NULL,
                content_digest TEXT NOT NULL,
                project_id TEXT,
                is_archived INTEGER NOT NULL DEFAULT 0,
                promoted_memory_id TEXT
            )
            """
        )
        try executeThrowing("CREATE INDEX IF NOT EXISTS idx_activities_ended_at ON activities(ended_at DESC)")
        try executeThrowing("CREATE INDEX IF NOT EXISTS idx_activities_context_key ON activities(context_key, ended_at DESC)")
        try executeThrowing("CREATE INDEX IF NOT EXISTS idx_activities_digest ON activities(content_digest)")
        try executeThrowing("CREATE INDEX IF NOT EXISTS idx_memories_context_source ON memories(context_source)")
        try executeThrowing(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS activity_fts USING fts5(
                id UNINDEXED,
                title,
                content,
                context_summary
            )
            """
        )
        try executeThrowing(
            """
            CREATE TABLE IF NOT EXISTS projects (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL UNIQUE COLLATE NOCASE,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                is_archived INTEGER NOT NULL DEFAULT 0
            )
            """
        )
        try executeThrowing(
            """
            CREATE TABLE IF NOT EXISTS memory_chunks (
                id TEXT PRIMARY KEY,
                memory_id TEXT NOT NULL,
                ordinal INTEGER NOT NULL,
                locator TEXT NOT NULL,
                content TEXT NOT NULL,
                UNIQUE(memory_id, ordinal)
            )
            """
        )
        try executeThrowing("CREATE INDEX IF NOT EXISTS idx_memory_chunks_memory ON memory_chunks(memory_id, ordinal)")
        try executeThrowing(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS memory_chunk_fts USING fts5(
                id UNINDEXED,
                memory_id UNINDEXED,
                locator,
                content
            )
            """
        )
        try executeThrowing(
            """
            CREATE TABLE IF NOT EXISTS embeddings (
                record_kind TEXT NOT NULL,
                record_id TEXT NOT NULL,
                model TEXT NOT NULL,
                dimension INTEGER NOT NULL,
                vector BLOB NOT NULL,
                updated_at REAL NOT NULL,
                PRIMARY KEY(record_kind, record_id, model)
            )
            """
        )
        try executeThrowing(
            """
            CREATE TABLE IF NOT EXISTS summary_runs (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                status TEXT NOT NULL,
                range_start REAL NOT NULL,
                range_end REAL NOT NULL,
                progress REAL NOT NULL,
                source_count INTEGER NOT NULL,
                result_memory_id TEXT,
                error_message TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """
        )
    }

    private func addV2Columns() throws {
        try addColumnIfMissing(table: "memories", name: "updated_at", definition: "REAL")
        try addColumnIfMissing(table: "memories", name: "project_id", definition: "TEXT")
        try addColumnIfMissing(table: "memories", name: "is_pinned", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfMissing(table: "memories", name: "source_references_json", definition: "TEXT NOT NULL DEFAULT '[]'")
        try executeThrowing("UPDATE memories SET updated_at = created_at WHERE updated_at IS NULL")

        try addColumnIfMissing(table: "action_items", name: "due_date", definition: "REAL")
        try addColumnIfMissing(table: "action_items", name: "priority", definition: "TEXT NOT NULL DEFAULT 'normal'")
        try addColumnIfMissing(table: "action_items", name: "status", definition: "TEXT NOT NULL DEFAULT 'open'")
        try addColumnIfMissing(table: "action_items", name: "updated_at", definition: "REAL")
        try addColumnIfMissing(table: "action_items", name: "reminder_identifier", definition: "TEXT")
        try executeThrowing(
            "UPDATE action_items SET status = CASE WHEN is_completed = 1 THEN 'completed' ELSE 'open' END"
        )
        try executeThrowing("UPDATE action_items SET updated_at = created_at WHERE updated_at IS NULL")
    }

    private func addColumnIfMissing(table: String, name: String, definition: String) throws {
        let columns = query("PRAGMA table_info(\(table))") { statement in
            v2ColumnText(statement, 1) ?? ""
        }
        guard !columns.contains(name) else { return }
        try executeThrowing("ALTER TABLE \(table) ADD COLUMN \(name) \(definition)")
    }

    private func migrateLegacyPassiveMemories() throws {
        let passiveSources = "'activeWindow','browser','ocr','typing'"
        try executeThrowing(
            """
            INSERT OR IGNORE INTO activities (
                id, source, context_key, content, context_app_name, context_bundle_id,
                context_window_title, context_page_title, context_url, started_at,
                ended_at, event_count, content_digest, project_id, is_archived, promoted_memory_id
            )
            SELECT id, context_source,
                   COALESCE(context_bundle_id, '') || '|' || COALESCE(context_url, '') || '|' || COALESCE(context_window_title, ''),
                   content, context_app_name, context_bundle_id, context_window_title,
                   context_page_title, context_url, created_at, created_at, 1, id,
                   project_id, 1, NULL
            FROM memories
            WHERE context_source IN (\(passiveSources))
            """
        )
        try executeThrowing(
            "DELETE FROM memory_fts WHERE id IN (SELECT id FROM memories WHERE context_source IN (\(passiveSources)))"
        )
        try executeThrowing("DELETE FROM memories WHERE context_source IN (\(passiveSources))")
        try executeThrowing("DELETE FROM activity_fts WHERE id IN (SELECT id FROM activities WHERE is_archived = 1)")
    }

    func loadRecentActivities(limit: Int = 100, includeArchived: Bool = false) -> [ActivitySession] {
        let archiveClause = includeArchived ? "" : "WHERE is_archived = 0"
        return query(
            """
            SELECT id, source, context_key, content, context_app_name, context_bundle_id,
                   context_window_title, context_page_title, context_url, started_at,
                   ended_at, event_count, content_digest, project_id, is_archived, promoted_memory_id
            FROM activities
            \(archiveClause)
            ORDER BY ended_at DESC
            LIMIT ?
            """,
            [.int(limit)]
        ) { statement in
            decodeActivity(statement)
        }
    }

    func loadActivity(id: UUID) -> ActivitySession? {
        query(
            """
            SELECT id, source, context_key, content, context_app_name, context_bundle_id,
                   context_window_title, context_page_title, context_url, started_at,
                   ended_at, event_count, content_digest, project_id, is_archived, promoted_memory_id
            FROM activities WHERE id = ? LIMIT 1
            """,
            [.text(id.uuidString)]
        ) { statement in decodeActivity(statement) }.first
    }

    func parentMemoryID(forChunkID id: UUID) -> UUID? {
        query("SELECT memory_id FROM memory_chunks WHERE id = ? LIMIT 1", [.text(id.uuidString)]) { statement in
            v2ColumnText(statement, 0).flatMap(UUID.init(uuidString:))
        }.first ?? nil
    }

    func mergeableActivity(contextKey: String, after date: Date) -> ActivitySession? {
        query(
            """
            SELECT id, source, context_key, content, context_app_name, context_bundle_id,
                   context_window_title, context_page_title, context_url, started_at,
                   ended_at, event_count, content_digest, project_id, is_archived, promoted_memory_id
            FROM activities
            WHERE context_key = ? AND ended_at >= ? AND is_archived = 0
            ORDER BY ended_at DESC LIMIT 1
            """,
            [.text(contextKey), .double(date.timeIntervalSince1970)]
        ) { statement in
            decodeActivity(statement)
        }.first
    }

    func activityExists(digest: String, since date: Date) -> Bool {
        (query(
            "SELECT 1 FROM activities WHERE content_digest = ? AND ended_at >= ? LIMIT 1",
            [.text(digest), .double(date.timeIntervalSince1970)]
        ) { _ in true }.first) ?? false
    }

    func upsertActivity(_ activity: ActivitySession) {
        let context = activity.context
        try? executeThrowing(
            """
            INSERT OR REPLACE INTO activities (
                id, source, context_key, content, context_app_name, context_bundle_id,
                context_window_title, context_page_title, context_url, started_at,
                ended_at, event_count, content_digest, project_id, is_archived, promoted_memory_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(activity.id.uuidString), .text(activity.source.rawValue), .text(activity.contextKey),
                .text(activity.content), .text(context?.appName), .text(context?.bundleIdentifier),
                .text(context?.windowTitle), .text(context?.pageTitle), .text(context?.url),
                .double(activity.startedAt.timeIntervalSince1970), .double(activity.endedAt.timeIntervalSince1970),
                .int(activity.eventCount), .text(activity.contentDigest), .text(activity.projectID?.uuidString),
                .int(activity.isArchived ? 1 : 0), .text(activity.promotedMemoryID?.uuidString)
            ]
        )
        try? executeThrowing("DELETE FROM activity_fts WHERE id = ?", [.text(activity.id.uuidString)])
        try? executeThrowing(
            "DELETE FROM embeddings WHERE record_kind = 'activity' AND record_id = ?",
            [.text(activity.id.uuidString)]
        )
        if !activity.isArchived {
            try? executeThrowing(
                "INSERT INTO activity_fts(id, title, content, context_summary) VALUES (?, ?, ?, ?)",
                [
                    .text(activity.id.uuidString), .text(activity.displayTitle), .text(activity.content),
                    .text(activity.context?.summary ?? "")
                ]
            )
        }
    }

    func archiveActivities(endingBefore date: Date) {
        try? executeThrowing(
            "UPDATE activities SET is_archived = 1 WHERE ended_at < ? AND promoted_memory_id IS NULL",
            [.double(date.timeIntervalSince1970)]
        )
        try? executeThrowing(
            "DELETE FROM activity_fts WHERE id IN (SELECT id FROM activities WHERE is_archived = 1)"
        )
        try? executeThrowing(
            "DELETE FROM embeddings WHERE record_kind = 'activity' AND record_id IN (SELECT id FROM activities WHERE is_archived = 1)"
        )
    }

    func activityCount(includeArchived: Bool = false) -> Int {
        let clause = includeArchived ? "" : " WHERE is_archived = 0"
        return query("SELECT COUNT(*) FROM activities\(clause)") { statement in
            Int(sqlite3_column_int64(statement, 0))
        }.first ?? 0
    }

    func memoryCount(category: MemoryCategory? = nil) -> Int {
        if let category {
            return query("SELECT COUNT(*) FROM memories WHERE category = ?", [.text(category.rawValue)]) { statement in
                Int(sqlite3_column_int64(statement, 0))
            }.first ?? 0
        }
        return query("SELECT COUNT(*) FROM memories") { statement in
            Int(sqlite3_column_int64(statement, 0))
        }.first ?? 0
    }

    var schemaVersion: Int {
        query("PRAGMA user_version") { statement in
            Int(sqlite3_column_int(statement, 0))
        }.first ?? 0
    }

    var databaseFileSize: Int64 {
        [databaseURL.path, databaseURL.path + "-wal", databaseURL.path + "-shm"].reduce(0) { total, path in
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?
                .int64Value ?? 0
            return total + size
        }
    }

    func loadMemories(category: MemoryCategory, limit: Int = 60) -> [MemoryItem] {
        query(
            "SELECT id FROM memories WHERE category = ? ORDER BY created_at DESC LIMIT ?",
            [.text(category.rawValue), .int(limit)]
        ) { statement in
            v2ColumnText(statement, 0).flatMap(UUID.init(uuidString:))
        }
        .compactMap { $0 }
        .compactMap(loadMemory(id:))
    }

    func loadSearchableRecords(startDate: Date?, limit: Int = 5_000) -> [SearchableRecord] {
        let timestamp = startDate?.timeIntervalSince1970 ?? 0
        let memoryLimit = max(1, limit * 2 / 5)
        let chunkLimit = max(1, limit * 2 / 5)
        let activityLimit = max(1, limit - memoryLimit - chunkLimit)
        var records = query(
            """
            SELECT id, title, content, created_at, context_app_name, context_window_title,
                   context_page_title, context_url, project_id, is_pinned
            FROM memories
            WHERE created_at >= ?
            ORDER BY is_pinned DESC, created_at DESC
            LIMIT ?
            """,
            [.double(timestamp), .int(memoryLimit)]
        ) { statement in
            let context = [
                v2ColumnText(statement, 4), v2ColumnText(statement, 5),
                v2ColumnText(statement, 6), v2ColumnText(statement, 7)
            ].compactMap { $0?.nilIfBlank }.joined(separator: " · ")
            let id = UUID(uuidString: v2ColumnText(statement, 0) ?? "") ?? UUID()
            return SearchableRecord(
                reference: RecordReference(kind: .memory, id: id),
                title: v2ColumnText(statement, 1) ?? "",
                content: v2ColumnText(statement, 2) ?? "",
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                locator: "",
                contextSummary: context,
                projectID: v2ColumnText(statement, 8).flatMap(UUID.init(uuidString:)),
                isPinned: sqlite3_column_int(statement, 9) == 1
            )
        }

        records.append(contentsOf: query(
                """
                SELECT c.id, m.title, c.content, m.created_at, c.locator, m.project_id, m.is_pinned
                FROM memory_chunks c
                JOIN memories m ON m.id = c.memory_id
                WHERE m.created_at >= ?
                ORDER BY m.created_at DESC, c.ordinal
                LIMIT ?
                """,
                [.double(timestamp), .int(chunkLimit)]
            ) { statement in
                SearchableRecord(
                    reference: RecordReference(
                        kind: .chunk,
                        id: UUID(uuidString: v2ColumnText(statement, 0) ?? "") ?? UUID()
                    ),
                    title: v2ColumnText(statement, 1) ?? "",
                    content: v2ColumnText(statement, 2) ?? "",
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                    locator: v2ColumnText(statement, 4) ?? "",
                    contextSummary: "本地文档",
                    projectID: v2ColumnText(statement, 5).flatMap(UUID.init(uuidString:)),
                    isPinned: sqlite3_column_int(statement, 6) == 1
                )
            })

        records.append(contentsOf: query(
                """
                SELECT id, source, content, context_app_name, context_window_title,
                       context_page_title, context_url, ended_at, project_id
                FROM activities
                WHERE ended_at >= ? AND is_archived = 0
                ORDER BY ended_at DESC
                LIMIT ?
                """,
                [.double(timestamp), .int(activityLimit)]
            ) { statement in
                let id = UUID(uuidString: v2ColumnText(statement, 0) ?? "") ?? UUID()
                let title = v2ColumnText(statement, 5)?.nilIfBlank
                    ?? v2ColumnText(statement, 4)?.nilIfBlank
                    ?? v2ColumnText(statement, 3)?.nilIfBlank
                    ?? v2ColumnText(statement, 1)
                    ?? "活动"
                let context = [v2ColumnText(statement, 3), v2ColumnText(statement, 4), v2ColumnText(statement, 6)]
                    .compactMap { $0?.nilIfBlank }
                    .joined(separator: " · ")
                return SearchableRecord(
                    reference: RecordReference(kind: .activity, id: id),
                    title: title,
                    content: v2ColumnText(statement, 2) ?? "",
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 7)),
                    locator: "",
                    contextSummary: context,
                    projectID: v2ColumnText(statement, 8).flatMap(UUID.init(uuidString:)),
                    isPinned: false
                )
            })
        return records
    }

    func fullTextMatchedReferences(query rawQuery: String, limit: Int = 200) -> Set<RecordReference> {
        let tokens = rawQuery
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        let match = tokens.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            .joined(separator: " OR ")
        guard !match.isEmpty else { return [] }

        var references = Set(query(
            "SELECT id FROM memory_fts WHERE memory_fts MATCH ? ORDER BY bm25(memory_fts) LIMIT ?",
            [.text(match), .int(limit)]
        ) { statement in
            RecordReference(
                kind: .memory,
                id: UUID(uuidString: v2ColumnText(statement, 0) ?? "") ?? UUID()
            )
        })
        references.formUnion(query(
            "SELECT id FROM activity_fts WHERE activity_fts MATCH ? ORDER BY bm25(activity_fts) LIMIT ?",
            [.text(match), .int(limit)]
        ) { statement in
            RecordReference(
                kind: .activity,
                id: UUID(uuidString: v2ColumnText(statement, 0) ?? "") ?? UUID()
            )
        })
        references.formUnion(query(
            "SELECT id FROM memory_chunk_fts WHERE memory_chunk_fts MATCH ? ORDER BY bm25(memory_chunk_fts) LIMIT ?",
            [.text(match), .int(limit)]
        ) { statement in
            RecordReference(
                kind: .chunk,
                id: UUID(uuidString: v2ColumnText(statement, 0) ?? "") ?? UUID()
            )
        })
        return references
    }

    func loadEmbedding(reference: RecordReference, model: String) -> [Float]? {
        let rows: [Data?] = query(
            "SELECT vector FROM embeddings WHERE record_kind = ? AND record_id = ? AND model = ? LIMIT 1",
            [.text(reference.kind.rawValue), .text(reference.id.uuidString), .text(model)],
            map: { statement -> Data? in
            guard let bytes = sqlite3_column_blob(statement, 0) else { return nil }
            return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            }
        )
        guard let data = rows.first ?? nil else { return nil }
        return data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }

    func upsertEmbedding(reference: RecordReference, model: String, vector: [Float]) {
        let data = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        var statement: OpaquePointer?
        let sql = """
        INSERT OR REPLACE INTO embeddings(record_kind, record_id, model, dimension, vector, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, reference.kind.rawValue, -1, SQLiteDatabase.transient)
        sqlite3_bind_text(statement, 2, reference.id.uuidString, -1, SQLiteDatabase.transient)
        sqlite3_bind_text(statement, 3, model, -1, SQLiteDatabase.transient)
        sqlite3_bind_int(statement, 4, Int32(vector.count))
        _ = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, 5, bytes.baseAddress, Int32(data.count), SQLiteDatabase.transient)
        }
        sqlite3_bind_double(statement, 6, Date().timeIntervalSince1970)
        sqlite3_step(statement)
    }

    func loadProjects() -> [MemoryProject] {
        query(
            "SELECT id, name, created_at, updated_at, is_archived FROM projects ORDER BY is_archived, updated_at DESC"
        ) { statement in
            MemoryProject(
                id: UUID(uuidString: v2ColumnText(statement, 0) ?? "") ?? UUID(),
                name: v2ColumnText(statement, 1) ?? "",
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                isArchived: sqlite3_column_int(statement, 4) == 1
            )
        }
    }

    func upsertProject(_ project: MemoryProject) {
        try? executeThrowing(
            "INSERT OR REPLACE INTO projects(id, name, created_at, updated_at, is_archived) VALUES (?, ?, ?, ?, ?)",
            [
                .text(project.id.uuidString), .text(project.name), .double(project.createdAt.timeIntervalSince1970),
                .double(project.updatedAt.timeIntervalSince1970), .int(project.isArchived ? 1 : 0)
            ]
        )
    }

    func replaceChunks(memoryID: UUID, chunks: [MemoryChunk]) {
        try? executeThrowing(
            "DELETE FROM embeddings WHERE record_kind = 'chunk' AND record_id IN (SELECT id FROM memory_chunks WHERE memory_id = ?)",
            [.text(memoryID.uuidString)]
        )
        try? executeThrowing("DELETE FROM memory_chunk_fts WHERE memory_id = ?", [.text(memoryID.uuidString)])
        try? executeThrowing("DELETE FROM memory_chunks WHERE memory_id = ?", [.text(memoryID.uuidString)])
        for chunk in chunks {
            try? executeThrowing(
                "INSERT INTO memory_chunks(id, memory_id, ordinal, locator, content) VALUES (?, ?, ?, ?, ?)",
                [.text(chunk.id.uuidString), .text(memoryID.uuidString), .int(chunk.ordinal), .text(chunk.locator), .text(chunk.content)]
            )
            try? executeThrowing(
                "INSERT INTO memory_chunk_fts(id, memory_id, locator, content) VALUES (?, ?, ?, ?)",
                [.text(chunk.id.uuidString), .text(memoryID.uuidString), .text(chunk.locator), .text(chunk.content)]
            )
        }
    }

    func loadChunks(memoryID: UUID) -> [MemoryChunk] {
        query(
            "SELECT id, memory_id, ordinal, locator, content FROM memory_chunks WHERE memory_id = ? ORDER BY ordinal",
            [.text(memoryID.uuidString)]
        ) { statement in
            MemoryChunk(
                id: UUID(uuidString: v2ColumnText(statement, 0) ?? "") ?? UUID(),
                memoryID: UUID(uuidString: v2ColumnText(statement, 1) ?? "") ?? memoryID,
                ordinal: Int(sqlite3_column_int(statement, 2)),
                locator: v2ColumnText(statement, 3) ?? "",
                content: v2ColumnText(statement, 4) ?? ""
            )
        }
    }

    func upsertSummaryRun(_ run: SummaryRun) {
        try? executeThrowing(
            """
            INSERT OR REPLACE INTO summary_runs (
                id, kind, status, range_start, range_end, progress, source_count,
                result_memory_id, error_message, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(run.id.uuidString), .text(run.kind.rawValue), .text(run.status.rawValue),
                .double(run.rangeStart.timeIntervalSince1970), .double(run.rangeEnd.timeIntervalSince1970),
                .double(run.progress), .int(run.sourceCount), .text(run.resultMemoryID?.uuidString),
                .text(run.errorMessage), .double(run.createdAt.timeIntervalSince1970),
                .double(run.updatedAt.timeIntervalSince1970)
            ]
        )
    }

    func loadSummaryRuns(limit: Int = 30) -> [SummaryRun] {
        query(
            """
            SELECT id, kind, status, range_start, range_end, progress, source_count,
                   result_memory_id, error_message, created_at, updated_at
            FROM summary_runs
            ORDER BY created_at DESC
            LIMIT ?
            """,
            [.int(limit)]
        ) { statement in
            SummaryRun(
                id: UUID(uuidString: v2ColumnText(statement, 0) ?? "") ?? UUID(),
                kind: SummaryRunKind(rawValue: v2ColumnText(statement, 1) ?? "") ?? .daily,
                status: SummaryRunStatus(rawValue: v2ColumnText(statement, 2) ?? "") ?? .failed,
                rangeStart: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                rangeEnd: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                progress: sqlite3_column_double(statement, 5),
                sourceCount: Int(sqlite3_column_int(statement, 6)),
                resultMemoryID: v2ColumnText(statement, 7).flatMap(UUID.init(uuidString:)),
                errorMessage: v2ColumnText(statement, 8) ?? "",
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 10))
            )
        }
    }

    func markInterruptedSummaryRunsFailed() {
        try? executeThrowing(
            """
            UPDATE summary_runs
            SET status = 'failed', error_message = '应用退出时总结尚未完成', updated_at = ?
            WHERE status IN ('waiting', 'running')
            """,
            [.double(Date().timeIntervalSince1970)]
        )
    }
}

private func decodeActivity(_ statement: OpaquePointer?) -> ActivitySession {
    let source = MemorySource(rawValue: v2ColumnText(statement, 1) ?? "") ?? .activeWindow
    let context = CapturedContext(
        source: source,
        appName: v2ColumnText(statement, 4),
        bundleIdentifier: v2ColumnText(statement, 5),
        windowTitle: v2ColumnText(statement, 6),
        pageTitle: v2ColumnText(statement, 7),
        url: v2ColumnText(statement, 8)
    )
    return ActivitySession(
        id: UUID(uuidString: v2ColumnText(statement, 0) ?? "") ?? UUID(),
        source: source,
        contextKey: v2ColumnText(statement, 2) ?? "",
        content: v2ColumnText(statement, 3) ?? "",
        context: context,
        startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)),
        endedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 10)),
        eventCount: Int(sqlite3_column_int(statement, 11)),
        contentDigest: v2ColumnText(statement, 12) ?? "",
        projectID: v2ColumnText(statement, 13).flatMap(UUID.init(uuidString:)),
        isArchived: sqlite3_column_int(statement, 14) == 1,
        promotedMemoryID: v2ColumnText(statement, 15).flatMap(UUID.init(uuidString:))
    )
}

private func v2ColumnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL,
          let text = sqlite3_column_text(statement, index) else { return nil }
    return String(cString: text)
}
