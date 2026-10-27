import Foundation
import NaturalLanguage

final class HybridMemorySearch {
    private let database: SQLiteDatabase
    private let modelName = "apple-nl-zh-sentence-v1"
    private let calendar = Calendar.current
    private let recentCandidateLimit = 180
    private let ftsCandidateLimit = 80
    private let maxNewEmbeddingsPerSearch = 48

    init(database: SQLiteDatabase) {
        self.database = database
    }

    func search(
        question: String,
        scope: MemoryQueryScope,
        projectID: UUID? = nil,
        limit: Int = 24
    ) -> [RankedMemoryResult] {
        let query = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let startDate: Date?
        switch scope {
        case .today:
            startDate = calendar.startOfDay(for: Date())
        case .lastSevenDays:
            startDate = calendar.date(byAdding: .day, value: -7, to: Date())
        case .all:
            startDate = nil
        }

        let textMatches = database.fullTextMatchedReferences(query: query, limit: ftsCandidateLimit)
        var seen = Set<RecordReference>()
        var candidates: [SearchableRecord] = []

        func append(_ records: [SearchableRecord]) {
            for record in records where seen.insert(record.reference).inserted {
                if projectID == nil || record.projectID == projectID {
                    candidates.append(record)
                }
            }
        }

        append(database.loadSearchableRecords(references: Array(textMatches), limit: ftsCandidateLimit))
        if candidates.count < recentCandidateLimit {
            append(
                database.loadSearchableRecords(
                    startDate: startDate,
                    limit: recentCandidateLimit - candidates.count
                )
            )
        }

        let queryVector: [Float]?
        if let values = Self.embeddingModel()?.vector(for: query) {
            queryVector = values.map { Float($0) }
        } else {
            queryVector = nil
        }

        let now = Date()
        var embeddingsGenerated = 0
        return candidates.compactMap { record -> RankedMemoryResult? in
            let semanticScore: Double
            if let queryVector,
               let candidateVector = vector(for: record, embeddingsGenerated: &embeddingsGenerated),
               candidateVector.count == queryVector.count {
                semanticScore = cosineSimilarity(queryVector, candidateVector)
            } else {
                semanticScore = 0
            }
            let textScore = textMatches.contains(record.reference)
                ? 1.0
                : lexicalOverlap(query, record.content + " " + record.title)
            let ageDays = max(0, now.timeIntervalSince(record.createdAt) / 86_400)
            let recencyScore = 1 / (1 + ageDays / 14)
            let pinScore = record.isPinned ? 1.0 : 0
            let score = semanticScore * 0.50 + textScore * 0.30 + recencyScore * 0.15 + pinScore * 0.05
            guard score > 0.08 else { return nil }
            return RankedMemoryResult(record: record, score: score)
        }
        .sorted { $0.score > $1.score }
        .prefix(limit)
        .map { $0 }
    }

    private func vector(for record: SearchableRecord, embeddingsGenerated: inout Int) -> [Float]? {
        if let stored = database.loadEmbedding(reference: record.reference, model: modelName) {
            return stored
        }
        guard embeddingsGenerated < maxNewEmbeddingsPerSearch else { return nil }
        guard let values = Self.embeddingModel()?.vector(for: record.title + "\n" + record.content.clipped(to: 4_000)) else {
            return nil
        }
        embeddingsGenerated += 1
        let generated = values.map { Float($0) }
        database.upsertEmbedding(reference: record.reference, model: modelName, vector: generated)
        return generated
    }

    private func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double {
        var dot: Double = 0
        var leftMagnitude: Double = 0
        var rightMagnitude: Double = 0
        for index in lhs.indices {
            let left = Double(lhs[index])
            let right = Double(rhs[index])
            dot += left * right
            leftMagnitude += left * left
            rightMagnitude += right * right
        }
        guard leftMagnitude > 0, rightMagnitude > 0 else { return 0 }
        return max(0, dot / (sqrt(leftMagnitude) * sqrt(rightMagnitude)))
    }

    private func lexicalOverlap(_ query: String, _ text: String) -> Double {
        let queryTokens = tokenSet(query)
        guard !queryTokens.isEmpty else { return 0 }
        let textTokens = tokenSet(text)
        return Double(queryTokens.intersection(textTokens).count) / Double(queryTokens.count)
    }

    private func tokenSet(_ text: String) -> Set<String> {
        let normalized = text.lowercased()
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = normalized
        var tokens = Set<String>()
        tokenizer.enumerateTokens(in: normalized.startIndex..<normalized.endIndex) { range, _ in
            let value = String(normalized[range]).trimmingCharacters(in: .punctuationCharacters)
            if value.count > 1 { tokens.insert(value) }
            return true
        }
        return tokens
    }

    private static let embeddingLock = NSLock()
    private static var cachedEmbedding: NLEmbedding?
    private static var didAttemptEmbedding = false

    static func embeddingModel() -> NLEmbedding? {
        embeddingLock.lock()
        defer { embeddingLock.unlock() }
        if didAttemptEmbedding {
            return cachedEmbedding
        }
        didAttemptEmbedding = true
        for language in [NLLanguage.simplifiedChinese, .english] {
            if let model = NLEmbedding.sentenceEmbedding(for: language) {
                cachedEmbedding = model
                return model
            }
        }
        return nil
    }
}
