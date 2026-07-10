import Foundation
import SQLite3
import XCTest
@testable import WorkMemory

final class WorkMemoryCoreTests: XCTestCase {
    func testV1MigrationPreservesManualMemoryAndArchivesPassiveRecords() throws {
        let directory = try temporaryDirectory()
        let databaseURL = directory.appendingPathComponent("workmemory.sqlite")
        try createV1Database(at: databaseURL)

        let database = try SQLiteDatabase(supportURL: directory)

        XCTAssertEqual(database.schemaVersion, 2)
        XCTAssertEqual(database.memoryCount(), 1)
        XCTAssertEqual(database.activityCount(), 0)
        XCTAssertEqual(database.activityCount(includeArchived: true), 1)
        let archivedFTSCount = database.query("SELECT COUNT(*) FROM activity_fts") {
            Int(sqlite3_column_int64($0, 0))
        }.first
        XCTAssertEqual(archivedFTSCount, 0)

        let backups = try FileManager.default.contentsOfDirectory(
            at: directory.appendingPathComponent("Backups"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(backups.filter { $0.pathExtension == "sqlite" }.count, 1)
    }

    func testPassiveCapturesMergeIntoTenMinuteActivitySession() throws {
        let directory = try temporaryDirectory()
        let store = MemoryStore(supportURL: directory)
        let now = Date()

        store.addCapturedMemory(PassiveCaptureSnapshot(
            source: .browser,
            content: "Alpha project overview",
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            windowTitle: "Alpha",
            pageTitle: "Alpha",
            url: "https://example.test/alpha",
            createdAt: now
        ))
        store.addCapturedMemory(PassiveCaptureSnapshot(
            source: .browser,
            content: "Alpha project rollout plan",
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            windowTitle: "Alpha",
            pageTitle: "Alpha",
            url: "https://example.test/alpha",
            createdAt: now.addingTimeInterval(90)
        ))

        XCTAssertEqual(store.activities.count, 1)
        XCTAssertEqual(store.activities[0].eventCount, 2)
        XCTAssertTrue(store.activities[0].content.contains("overview"))
        XCTAssertTrue(store.activities[0].content.contains("rollout"))
        XCTAssertEqual(store.webPageItems(for: .today).count, 1)
        XCTAssertEqual(store.queryItems(for: .today).filter { $0.context?.source == .browser }.count, 1)
    }

    func testDocumentChunkerPreservesLocatorAndOverlap() {
        let text = String(repeating: "A", count: 1_250) + String(repeating: "B", count: 300)
        let document = ExtractedDocumentText(
            sections: [.init(locator: "第 3 页", text: text)],
            format: "pdf"
        )

        let chunks = DocumentChunker().chunks(for: document, memoryID: UUID())

        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks.map(\.locator), ["第 3 页", "第 3 页"])
        XCTAssertEqual(String(chunks[0].content.suffix(150)), String(chunks[1].content.prefix(150)))
    }

    func testXLSXExtractionResolvesSharedStrings() throws {
        let directory = try temporaryDirectory()
        let source = directory.appendingPathComponent("fixture", isDirectory: true)
        let worksheetDirectory = source.appendingPathComponent("xl/worksheets", isDirectory: true)
        try FileManager.default.createDirectory(at: worksheetDirectory, withIntermediateDirectories: true)
        try Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
              <si><t>WorkMemory 版本发布状态</t></si><si><t>已完成全部发布检查</t></si>
            </sst>
            """.utf8
        ).write(to: source.appendingPathComponent("xl/sharedStrings.xml"))
        try Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
              <row><c t="s"><v>0</v></c><c t="s"><v>1</v></c></row>
            </sheetData></worksheet>
            """.utf8
        ).write(to: worksheetDirectory.appendingPathComponent("sheet1.xml"))
        let archive = directory.appendingPathComponent("fixture.xlsx")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qr", archive.path, "."]
        process.currentDirectoryURL = source
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let extracted = try DocumentTextExtractor().extract(from: archive)

        XCTAssertEqual(extracted.sections.first?.locator, "Sheet 1")
        XCTAssertTrue(extracted.text.contains("WorkMemory 版本发布状态"))
        XCTAssertTrue(extracted.text.contains("已完成全部发布检查"))
    }

    func testHybridSearchReturnsExactFullTextEvidence() throws {
        let directory = try temporaryDirectory()
        let database = try SQLiteDatabase(supportURL: directory)
        let target = MemoryItem(
            title: "Alpha rollout decision",
            content: "The team approved the zircon launch checklist.",
            category: .decision
        )
        database.upsertMemory(target)
        database.upsertMemory(MemoryItem(
            title: "Unrelated note",
            content: "Lunch options for Friday.",
            category: .note
        ))

        let results = HybridMemorySearch(database: database).search(
            question: "zircon launch",
            scope: .all,
            limit: 5
        )

        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results.first?.record.reference, RecordReference(kind: .memory, id: target.id))
    }

    func testLegacyActionItemDecodesCompletionState() throws {
        let data = Data(
            """
            {
              "id": "9C1E63E1-38CD-4C96-BB48-255B91F763E2",
              "title": "Ship release",
              "project": "WorkMemory",
              "owner": "",
              "dueDateText": "",
              "evidence": "approved",
              "sourceTitle": "decision",
              "isCompleted": true
            }
            """.utf8
        )

        let item = try JSONDecoder().decode(WorkActionItem.self, from: data)

        XCTAssertEqual(item.status, .completed)
        XCTAssertEqual(item.priority, .normal)
        XCTAssertTrue(item.isCompleted)
    }

    func testSummaryRunRoundTripAndInterruptedRecovery() throws {
        let directory = try temporaryDirectory()
        let database = try SQLiteDatabase(supportURL: directory)
        let now = Date()
        let run = SummaryRun(
            id: UUID(),
            kind: .daily,
            status: .running,
            rangeStart: now.addingTimeInterval(-300),
            rangeEnd: now,
            progress: 0.4,
            sourceCount: 12,
            resultMemoryID: nil,
            errorMessage: "",
            createdAt: now,
            updatedAt: now
        )
        database.upsertSummaryRun(run)

        database.markInterruptedSummaryRunsFailed()
        let recovered = try XCTUnwrap(database.loadSummaryRuns().first)

        XCTAssertEqual(recovered.id, run.id)
        XCTAssertEqual(recovered.status, .failed)
        XCTAssertFalse(recovered.errorMessage.isEmpty)
    }

    func testV2DatabaseRepairsLateLegacyPassiveWrites() throws {
        let directory = try temporaryDirectory()
        var database: SQLiteDatabase? = try SQLiteDatabase(supportURL: directory)
        let lateID = UUID()
        try database?.executeThrowing(
            """
            INSERT INTO memories (
                id, title, content, category, action_items_json, created_at,
                context_source, context_app_name, context_bundle_id,
                context_window_title, context_page_title, context_url
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(lateID.uuidString), .text("Late browser row"), .text("Preserve this context"),
                .text("web"), .text("[]"), .double(Date().timeIntervalSince1970),
                .text("browser"), .text("Safari"), .text("com.apple.Safari"),
                .text("Late page"), .text("Late page"), .text("https://example.test/late")
            ]
        )
        database = nil

        database = try SQLiteDatabase(supportURL: directory)

        XCTAssertNil(database?.loadMemory(id: lateID))
        XCTAssertEqual(database?.activityCount(includeArchived: true), 1)
        XCTAssertEqual(database?.loadActivity(id: lateID)?.content, "Preserve this context")
    }

    func testDeletingMemoryRemovesChunksAndEmbeddingCache() throws {
        let directory = try temporaryDirectory()
        let database = try SQLiteDatabase(supportURL: directory)
        let memory = MemoryItem(title: "Document", content: "Summary", category: .document)
        let chunk = MemoryChunk(memoryID: memory.id, ordinal: 0, locator: "第 1 页", content: "Source text")
        database.upsertMemory(memory)
        database.replaceChunks(memoryID: memory.id, chunks: [chunk])
        database.upsertEmbedding(
            reference: RecordReference(kind: .memory, id: memory.id),
            model: "test",
            vector: [1, 0]
        )
        database.upsertEmbedding(
            reference: RecordReference(kind: .chunk, id: chunk.id),
            model: "test",
            vector: [0, 1]
        )

        database.deleteMemory(id: memory.id)

        XCTAssertTrue(database.loadChunks(memoryID: memory.id).isEmpty)
        XCTAssertNil(database.loadEmbedding(reference: .init(kind: .memory, id: memory.id), model: "test"))
        XCTAssertNil(database.loadEmbedding(reference: .init(kind: .chunk, id: chunk.id), model: "test"))
    }

    func testLargeWorkspaceStartupFixtureWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["WORKMEMORY_LARGE_FIXTURE_DIR"] else {
            throw XCTSkip("Set WORKMEMORY_LARGE_FIXTURE_DIR to run the large-workspace startup check")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let startedAt = Date()

        let store = MemoryStore(supportURL: directory)
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertGreaterThan(store.totalMemoryCount + store.archivedActivityCount, 40_000)
        XCTAssertLessThan(elapsed, 3.0)
        print(String(format: "Large workspace initialized in %.3f seconds", elapsed))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkMemoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func createV1Database(at url: URL) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            XCTFail("Unable to create v1 fixture")
            return
        }
        defer { sqlite3_close(handle) }
        let now = Date().timeIntervalSince1970
        let sql = """
        CREATE TABLE memories (
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
        );
        INSERT INTO memories VALUES (
            '00000000-0000-0000-0000-000000000001', 'Manual', 'Keep me', 'note', '[]', \(now),
            'manual', NULL, NULL, NULL, NULL, NULL
        );
        INSERT INTO memories VALUES (
            '00000000-0000-0000-0000-000000000002', 'Browser', 'Archive me', 'web', '[]', \(now),
            'browser', 'Safari', 'com.apple.Safari', 'Page', 'Page', 'https://example.test'
        );
        PRAGMA user_version = 1;
        """
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown sqlite error"
            sqlite3_free(error)
            XCTFail(message)
            return
        }
    }
}
