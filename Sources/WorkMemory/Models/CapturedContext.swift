import Foundation

struct CapturedContext: Codable, Hashable {
    var source: MemorySource
    var appName: String?
    var bundleIdentifier: String?
    var windowTitle: String?
    var pageTitle: String?
    var url: String?

    var summary: String {
        var parts: [String] = [source.label]

        if let appName, !appName.isEmpty {
            parts.append(appName)
        }

        if let pageTitle, !pageTitle.isEmpty {
            parts.append(pageTitle)
        } else if let windowTitle, !windowTitle.isEmpty {
            parts.append(windowTitle)
        }

        if let url, !url.isEmpty {
            parts.append(url)
        }

        return parts.joined(separator: " · ")
    }
}
