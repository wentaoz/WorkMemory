import Foundation

enum SecurityScopedFolder {
    static func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolve(bookmark: Data?, fallbackPath: String) -> URL {
        guard let bookmark else { return URL(fileURLWithPath: fallbackPath, isDirectory: true) }
        var stale = false
        return (try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )) ?? URL(fileURLWithPath: fallbackPath, isDirectory: true)
    }

    static func access<T>(_ url: URL, _ operation: () throws -> T) rethrows -> T {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try operation()
    }
}
