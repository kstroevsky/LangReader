import Foundation
import SQLite3

private let VOCABULARY_DOMAIN_SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

package enum VocabularyDocumentDomain: String, Codable, CaseIterable, Equatable, Sendable {
    case general
    case literary
    case news
    case technicalReference
}

package struct VocabularyDomainResourceMetadata: Codable, Equatable, Sendable {
    package let resourceID: String
    package let languageCode: String
    package let domain: VocabularyDocumentDomain
    package let source: String
    package let sourceVersion: String
    package let sourceChecksum: String
    package let derivedChecksum: String
    package let rowCount: Int
    package let attribution: String

    package init(
        resourceID: String,
        languageCode: String,
        domain: VocabularyDocumentDomain,
        source: String,
        sourceVersion: String,
        sourceChecksum: String,
        derivedChecksum: String,
        rowCount: Int = 200_000,
        attribution: String
    ) {
        self.resourceID = resourceID
        self.languageCode = languageCode
        self.domain = domain
        self.source = source
        self.sourceVersion = sourceVersion
        self.sourceChecksum = sourceChecksum
        self.derivedChecksum = derivedChecksum
        self.rowCount = rowCount
        self.attribution = attribution
    }
}

/// Immutable rank lookup used only by the developer-gated domain experiment.
package final class VocabularyDomainRankTable: @unchecked Sendable {
    package static let maximumRank = 200_000

    package let metadata: VocabularyDomainResourceMetadata
    private let databaseURLs: [URL]
    private let lock = NSLock()
    private var database: OpaquePointer?

    package init(metadata: VocabularyDomainResourceMetadata, databaseURLs: [URL]? = nil) {
        self.metadata = metadata
        self.databaseURLs = databaseURLs ?? Self.defaultDatabaseURLs(resourceID: metadata.resourceID)
    }

    deinit {
        lock.withLock {
            if let database { sqlite3_close(database) }
            database = nil
        }
    }

    package var isInstalled: Bool {
        databaseURLs.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    package func rank(for word: String) -> Int? {
        let key = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        return lock.withLock {
            guard let database = openDatabase() else { return nil }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database,
                "SELECT rank FROM word_rank WHERE word_key = ? LIMIT 1",
                -1,
                &statement,
                nil
            ) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, key, -1, VOCABULARY_DOMAIN_SQLITE_TRANSIENT)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return Int(sqlite3_column_int(statement, 0))
        }
    }

    package func bestRank(for summary: VocabularyDocumentLemmaSummary) -> Int? {
        ([summary.displayLemma] + summary.observedForms.map(\.surface)).compactMap(rank(for:)).min()
    }

    package func rowCount() -> Int? {
        lock.withLock {
            guard let database = openDatabase() else { return nil }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM word_rank", -1, &statement, nil) == SQLITE_OK else {
                return nil
            }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return Int(sqlite3_column_int(statement, 0))
        }
    }

    private func openDatabase() -> OpaquePointer? {
        if let database { return database }
        guard let url = databaseURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { return nil }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            return nil
        }
        database = handle
        return handle
    }

    private static func defaultDatabaseURLs(resourceID: String) -> [URL] {
        var roots: [URL] = []
        if let resources = Bundle.main.resourceURL {
            roots.append(resources.appendingPathComponent("VocabularyDomains", isDirectory: true))
            roots.append(resources)
        }
        roots.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources/LeafReaderApp/Resources/VocabularyDomains", isDirectory: true)
        )
        return roots.map { $0.appendingPathComponent("\(resourceID).sqlite") }
    }
}

package struct VocabularyDocumentDomainScore: Codable, Equatable, Sendable {
    package let domain: VocabularyDocumentDomain
    package let normalizedCrossEntropy: Double
}

package struct VocabularyDocumentDomainDetection: Codable, Equatable, Sendable {
    package let suggestedDomain: VocabularyDocumentDomain
    package let scores: [VocabularyDocumentDomainScore]
    package let bestVersusSecondMargin: Double
    package let usedGeneralFallback: Bool
}

/// A lexical rank cross-entropy heuristic. It records domain metadata without
/// affecting the production cold-start difficulty provider.
package struct VocabularyDocumentDomainDetector: Sendable {
    package let tables: [VocabularyDomainRankTable]

    package init(tables: [VocabularyDomainRankTable]) {
        self.tables = tables
    }

    package func detect(
        summaries: [VocabularyDocumentLemmaSummary],
        languageCode: String
    ) -> VocabularyDocumentDomainDetection {
        let eligible = tables.filter { $0.metadata.languageCode == languageCode && $0.isInstalled }
        let weighted = summaries.filter { !$0.isConfidentName }.prefix(2_000)
        let denominator = weighted.reduce(0.0) { $0 + log1p(Double($1.occurrenceCount)) }
        let scores = eligible.map { table in
            let total = weighted.reduce(0.0) { partial, summary in
                let rank = table.bestRank(for: summary)
                let information = rank.map {
                    log1p(Double($0)) / log1p(Double(VocabularyDomainRankTable.maximumRank))
                } ?? 1.15
                return partial + log1p(Double(summary.occurrenceCount)) * information
            }
            return VocabularyDocumentDomainScore(
                domain: table.metadata.domain,
                normalizedCrossEntropy: denominator > 0 ? total / denominator : 1.15
            )
        }.sorted {
            if $0.normalizedCrossEntropy != $1.normalizedCrossEntropy {
                return $0.normalizedCrossEntropy < $1.normalizedCrossEntropy
            }
            return $0.domain.rawValue < $1.domain.rawValue
        }
        guard let best = scores.first else {
            return VocabularyDocumentDomainDetection(
                suggestedDomain: .general,
                scores: [],
                bestVersusSecondMargin: 0,
                usedGeneralFallback: true
            )
        }
        let margin: Double
        if scores.count > 1 {
            margin = max(0, (scores[1].normalizedCrossEntropy - best.normalizedCrossEntropy)
                / max(scores[1].normalizedCrossEntropy, 0.000_001))
        } else {
            margin = 1
        }
        let fallback = margin < 0.05
        return VocabularyDocumentDomainDetection(
            suggestedDomain: fallback ? .general : best.domain,
            scores: scores,
            bestVersusSecondMargin: margin,
            usedGeneralFallback: fallback
        )
    }
}

package enum VocabularyDocumentDomainResources {
    package static let metadata: [VocabularyDomainResourceMetadata] = [
        VocabularyDomainResourceMetadata(
            resourceID: "eng_fiction_20200217",
            languageCode: "en",
            domain: .literary,
            source: "Google Books English Fiction one-grams",
            sourceVersion: "20200217",
            sourceChecksum: "md5:d4b8b7b0654313359da3eef00c48aafd",
            derivedChecksum: "pending",
            attribution: "Google Books Ngram Viewer, CC BY 3.0"
        ),
        VocabularyDomainResourceMetadata(
            resourceID: "ger_20200217",
            languageCode: "de",
            domain: .literary,
            source: "Google Books German one-grams",
            sourceVersion: "20200217",
            sourceChecksum: "md5:66e38f0b…64463f4b (8 pinned shards)",
            derivedChecksum: "pending",
            attribution: "Google Books Ngram Viewer, CC BY 3.0"
        ),
        VocabularyDomainResourceMetadata(
            resourceID: "eng_news_2025_1M",
            languageCode: "en",
            domain: .news,
            source: "Leipzig Corpora Collection",
            sourceVersion: "eng_news_2025_1M",
            sourceChecksum: "sha256:7cad9136013d27b6230841558d19c5ab39b18c502dce8ccd3a821fdf74b4081b",
            derivedChecksum: "sha256:464e8aa23a84a17a29940b7288a7eae1a3f28f9e3c0b74903b00b89977c06a11",
            attribution: "© Universität Leipzig, CC BY"
        ),
        VocabularyDomainResourceMetadata(
            resourceID: "deu_news_2025_1M",
            languageCode: "de",
            domain: .news,
            source: "Leipzig Corpora Collection",
            sourceVersion: "deu_news_2025_1M",
            sourceChecksum: "sha256:2c55dbe53158bb06c323bfa30407972c219c70a643bbad50cc6b08221fa34e7a",
            derivedChecksum: "sha256:508bd6e7cd9e78b67718a5a2e2189cf739173c5bc29a5a9f0d662fad9e8ecdcb",
            attribution: "© Universität Leipzig, CC BY"
        ),
        VocabularyDomainResourceMetadata(
            resourceID: "eng_wikipedia_2016_1M",
            languageCode: "en",
            domain: .technicalReference,
            source: "Leipzig Corpora Collection",
            sourceVersion: "eng_wikipedia_2016_1M",
            sourceChecksum: "sha256:42cc4e689b93a320151fa4378572db9d6c5a5eee6e13c966fdefe77954d6596d",
            derivedChecksum: "sha256:ff74303e041b58df932cea099bc6598089178ce80e6e6873c27d05600c23387e",
            attribution: "© Universität Leipzig, CC BY"
        ),
        VocabularyDomainResourceMetadata(
            resourceID: "deu_wikipedia_2021_1M",
            languageCode: "de",
            domain: .technicalReference,
            source: "Leipzig Corpora Collection",
            sourceVersion: "deu_wikipedia_2021_1M",
            sourceChecksum: "sha256:d5eb95fe71010a88d69ba408a4016f67a3a219e1a63cade652593abf33010aba",
            derivedChecksum: "sha256:673ba8a14b1a087a45bca98077b4ede06bbd343425b0742807d2cd6f9c2fee9f",
            attribution: "© Universität Leipzig, CC BY"
        )
    ]

    package static let tables: [VocabularyDomainRankTable] = metadata.map { item in
        if item.resourceID == "deu_news_2025_1M" {
            var urls: [URL] = []
            if let resources = Bundle.main.resourceURL {
                urls.append(resources.appendingPathComponent("GermanFrequency/deu_news_2025_1M.sqlite"))
            }
            urls.append(
                URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent("Sources/LeafReaderApp/Resources/GermanFrequency/deu_news_2025_1M.sqlite")
            )
            return VocabularyDomainRankTable(metadata: item, databaseURLs: urls)
        }
        return VocabularyDomainRankTable(metadata: item)
    }

    package static let detector = VocabularyDocumentDomainDetector(tables: tables)
}

/// Reserved experiment boundary. Callers must explicitly enable it; the live
/// preparation flow continues using the general-language provider.
package struct ExperimentalDomainBlendedDifficultyProvider: DocumentVocabularyDifficultyProviding {
    package let frequencyScale: VocabularyFrequencyScale
    private let general: any DocumentVocabularyDifficultyProviding
    private let table: VocabularyDomainRankTable
    private let domainWeight: Double

    package init(
        general: any DocumentVocabularyDifficultyProviding,
        table: VocabularyDomainRankTable,
        domainWeight: Double = 0.30
    ) {
        self.general = general
        self.table = table
        self.domainWeight = min(max(domainWeight, 0), 1)
        frequencyScale = VocabularyFrequencyScale(
            sourceID: "experimental-blend:\(general.frequencyScale.sourceID)+\(table.metadata.resourceID)",
            version: "developer-only-v1",
            maximumRank: general.frequencyScale.maximumRank
        )
    }

    package func bestRank(for summary: VocabularyDocumentLemmaSummary) -> Int? {
        general.bestRank(for: summary)
    }

    package func difficultyPrior(for summary: VocabularyDocumentLemmaSummary) -> VocabularyItemDifficultyPrior {
        let generalPrior = general.difficultyPrior(for: summary)
        let domainPrior = VocabularyItemDifficultyPrior.frequencyRank(
            table.bestRank(for: summary),
            scale: VocabularyFrequencyScale(
                sourceID: table.metadata.resourceID,
                version: table.metadata.sourceVersion,
                maximumRank: VocabularyDomainRankTable.maximumRank
            )
        )
        return VocabularyItemDifficultyPrior(
            mean: generalPrior.mean * (1 - domainWeight) + domainPrior.mean * domainWeight,
            standardDeviation: max(generalPrior.standardDeviation, domainPrior.standardDeviation),
            source: .rankedFrequency,
            version: frequencyScale.version
        )
    }
}
