import Foundation

struct PassiveCaptureSnapshot {
    var source: MemorySource
    var content: String
    var appName: String?
    var bundleIdentifier: String?
    var windowTitle: String?
    var pageTitle: String?
    var url: String?
    var createdAt: Date = Date()

    var context: CapturedContext {
        CapturedContext(
            source: source,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            pageTitle: pageTitle,
            url: url
        )
    }
}
