import Foundation
import SQLite3
import XCTest
import LeafReaderCore

final class VocabularyDocumentDomainXCTests: XCTestCase {
    func testPinnedInstalledDomainResourcesHaveExpectedRows() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/LeafReaderApp/Resources/VocabularyDomains")
        for resourceID in [
            "eng_fiction_20200217",
            "ger_20200217",
            "eng_news_2025_1M",
            "eng_wikipedia_2016_1M",
            "deu_wikipedia_2021_1M"
        ] {
            let metadata = try XCTUnwrap(VocabularyDocumentDomainResources.metadata.first { $0.resourceID == resourceID })
            XCTAssertTrue(metadata.sourceChecksum.contains(":"))
            XCTAssertTrue(metadata.derivedChecksum.hasPrefix("sha256:"))
            let table = VocabularyDomainRankTable(
                metadata: metadata,
                databaseURLs: [root.appendingPathComponent("\(resourceID).sqlite")]
            )
            XCTAssertEqual(
                DocumentContentFingerprint.sha256(
                    for: root.appendingPathComponent("\(resourceID).sqlite")
                ),
                metadata.derivedChecksum.replacingOccurrences(of: "sha256:", with: ""),
                resourceID
            )
            XCTAssertEqual(table.rowCount(), 200_000, resourceID)
            XCTAssertNotNil(table.rank(for: metadata.languageCode == "de" ? "der" : "the"), resourceID)
        }
    }

    func testDetectorFallsBackBelowFivePercentAndSelectsClearDomain() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let literary = try table(
            at: root.appendingPathComponent("literary.sqlite"),
            domain: .literary,
            ranks: ["moon": 1, "castle": 2, "machine": 199_000]
        )
        let technical = try table(
            at: root.appendingPathComponent("technical.sqlite"),
            domain: .technicalReference,
            ranks: ["machine": 1, "moon": 190_000, "castle": 195_000]
        )
        let detector = VocabularyDocumentDomainDetector(tables: [literary, technical])
        let clear = detector.detect(
            summaries: [summary("moon", count: 8), summary("castle", count: 6)],
            languageCode: "en"
        )
        XCTAssertEqual(clear.suggestedDomain, .literary)
        XCTAssertFalse(clear.usedGeneralFallback)

        let tied = try table(
            at: root.appendingPathComponent("tied.sqlite"),
            domain: .news,
            ranks: ["moon": 1, "castle": 2]
        )
        let fallback = VocabularyDocumentDomainDetector(tables: [literary, tied]).detect(
            summaries: [summary("moon", count: 8), summary("castle", count: 6)],
            languageCode: "en"
        )
        XCTAssertEqual(fallback.suggestedDomain, .general)
        XCTAssertTrue(fallback.usedGeneralFallback)
    }

    private func summary(_ word: String, count: Int) -> VocabularyDocumentLemmaSummary {
        VocabularyDocumentLemmaSummary(
            canonicalKey: word,
            displayLemma: word,
            observedForms: [VocabularyDocumentObservedForm(surface: word, occurrenceCount: count)],
            occurrenceCount: count,
            representativeRange: VocabularyDocumentSourceRange(unitIndex: 0, utf16Location: 0, utf16Length: word.count)
        )
    }

    private func table(
        at url: URL,
        domain: VocabularyDocumentDomain,
        ranks: [String: Int]
    ) throws -> VocabularyDomainRankTable {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, "CREATE TABLE word_rank(word_key TEXT PRIMARY KEY, rank INTEGER NOT NULL)", nil, nil, nil), SQLITE_OK)
        for (word, rank) in ranks {
            XCTAssertEqual(sqlite3_exec(database, "INSERT INTO word_rank VALUES ('\(word)', \(rank))", nil, nil, nil), SQLITE_OK)
        }
        return VocabularyDomainRankTable(
            metadata: VocabularyDomainResourceMetadata(
                resourceID: url.deletingPathExtension().lastPathComponent,
                languageCode: "en",
                domain: domain,
                source: "fixture",
                sourceVersion: "v1",
                sourceChecksum: "sha256:fixture",
                derivedChecksum: "sha256:fixture",
                rowCount: ranks.count,
                attribution: "fixture"
            ),
            databaseURLs: [url]
        )
    }
}
