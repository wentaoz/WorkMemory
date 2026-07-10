import Foundation

struct ActivitySession: Identifiable, Codable, Hashable {
    let id: UUID
    var source: MemorySource
    var contextKey: String
    var content: String
    var context: CapturedContext?
    var startedAt: Date
    var endedAt: Date
    var eventCount: Int
    var contentDigest: String
    var projectID: UUID?
    var isArchived: Bool
    var promotedMemoryID: UUID?

    init(
        id: UUID = UUID(),
        source: MemorySource,
        contextKey: String,
        content: String,
        context: CapturedContext?,
        startedAt: Date = Date(),
        endedAt: Date = Date(),
        eventCount: Int = 1,
        contentDigest: String,
        projectID: UUID? = nil,
        isArchived: Bool = false,
        promotedMemoryID: UUID? = nil
    ) {
        self.id = id
        self.source = source
        self.contextKey = contextKey
        self.content = content
        self.context = context
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.eventCount = eventCount
        self.contentDigest = contentDigest
        self.projectID = projectID
        self.isArchived = isArchived
        self.promotedMemoryID = promotedMemoryID
    }

    var duration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }

    var displayTitle: String {
        context?.pageTitle?.nilIfBlank
            ?? context?.windowTitle?.nilIfBlank
            ?? context?.appName?.nilIfBlank
            ?? source.label
    }
}
