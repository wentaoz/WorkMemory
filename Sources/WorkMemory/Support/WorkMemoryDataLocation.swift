import Foundation

enum WorkMemoryDataLocation {
    private static let environmentKey = "WORKMEMORY_DATA_DIR"

    static func supportURL(fileManager: FileManager = .default) -> URL {
        if let path = ProcessInfo.processInfo.environment[environmentKey]?.nilIfBlank {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("WorkMemory", isDirectory: true)
        ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WorkMemory", isDirectory: true)
    }
}
