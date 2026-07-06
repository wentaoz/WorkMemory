import Combine
import Foundation

enum AppLogLevel: String, Codable, CaseIterable, Identifiable {
    case info
    case warning
    case error

    var id: String { rawValue }

    var label: String {
        switch self {
        case .info:
            return "信息"
        case .warning:
            return "警告"
        case .error:
            return "错误"
        }
    }
}

struct AppLogEntry: Identifiable, Codable {
    let id: UUID
    var createdAt: Date
    var level: AppLogLevel
    var category: String
    var message: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        level: AppLogLevel,
        category: String,
        message: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.level = level
        self.category = category
        self.message = message
    }

    var displayText: String {
        "[\(DateFormatting.dateTime.string(from: createdAt))] [\(level.label)] [\(category)] \(message)"
    }
}

final class AppLogStore: ObservableObject {
    static let shared = AppLogStore()

    @Published private(set) var entries: [AppLogEntry] = []

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let maxEntries = 500

    private init(fileManager: FileManager = .default) {
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("WorkMemory", isDirectory: true)
        ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WorkMemory", isDirectory: true)

        try? fileManager.createDirectory(at: supportURL, withIntermediateDirectories: true)
        fileURL = supportURL.appendingPathComponent("runtime-log.jsonl")
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        entries = loadEntries()
    }

    func info(_ message: String, category: String) {
        add(level: .info, category: category, message: message)
    }

    func warning(_ message: String, category: String) {
        add(level: .warning, category: category, message: message)
    }

    func error(_ message: String, category: String) {
        add(level: .error, category: category, message: message)
    }

    func clear() {
        runOnMain {
            self.entries.removeAll()
            try? Data().write(to: self.fileURL)
        }
    }

    func copyText() -> String {
        entries.map(\.displayText).joined(separator: "\n")
    }

    private func add(level: AppLogLevel, category: String, message: String) {
        let entry = AppLogEntry(
            level: level,
            category: category,
            message: message.clipped(to: 4_000)
        )

        runOnMain {
            self.entries.insert(entry, at: 0)
            if self.entries.count > self.maxEntries {
                self.entries.removeLast(self.entries.count - self.maxEntries)
            }
            self.appendToFile(entry)
        }
    }

    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func appendToFile(_ entry: AppLogEntry) {
        guard let data = try? encoder.encode(entry) else { return }
        var line = data
        line.append(0x0A)

        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: fileURL)
        }
    }

    private func loadEntries() -> [AppLogEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let rawText = String(data: data, encoding: .utf8) else {
            return []
        }

        let decodedEntries: [AppLogEntry] = rawText
            .components(separatedBy: .newlines)
            .compactMap { line -> AppLogEntry? in
                guard let data = line.data(using: .utf8), !line.isEmpty else { return nil }
                return try? decoder.decode(AppLogEntry.self, from: data)
            }

        return Array(decodedEntries.suffix(maxEntries).reversed())
    }
}
