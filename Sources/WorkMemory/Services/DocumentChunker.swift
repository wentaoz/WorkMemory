import Foundation

struct DocumentChunker {
    let targetLength = 1_400
    let overlapLength = 150

    func chunks(for document: ExtractedDocumentText, memoryID: UUID) -> [MemoryChunk] {
        var result: [MemoryChunk] = []
        for section in document.sections {
            let text = section.text
            var start = text.startIndex
            while start < text.endIndex {
                let end = text.index(start, offsetBy: targetLength, limitedBy: text.endIndex) ?? text.endIndex
                let content = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !content.isEmpty {
                    result.append(MemoryChunk(
                        memoryID: memoryID,
                        ordinal: result.count,
                        locator: section.locator,
                        content: content
                    ))
                }
                guard end < text.endIndex else { break }
                start = text.index(end, offsetBy: -min(overlapLength, text.distance(from: start, to: end)))
            }
        }
        return result
    }
}
