import Foundation
import XCTest
import LeafReaderCore

final class GermanFrequencyRankTableXCTests: XCTestCase {
    func testDifficultyProvidersExposePinnedVersionedScales() throws {
        let englishURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/LeafReaderApp/Resources/ECDICT/ecdict.db")
        let dictionary = ECDICTDictionary(databaseURLs: [englishURL], csvURLs: [])
        let english = ECDICTDocumentVocabularyDifficultyProvider(
            dictionary: LocalDictionaryLookupService(dictionary: dictionary)
        )
        let german = GermanCorpusDocumentVocabularyDifficultyProvider()

        XCTAssertEqual(dictionary.maximumFrequencyRank(), 47_062)
        XCTAssertEqual(english.frequencyScale.maximumRank, 47_062)
        XCTAssertEqual(english.frequencyScale.sourceID, "ECDICT.frq")
        XCTAssertEqual(german.frequencyScale.maximumRank, 200_000)
        XCTAssertEqual(german.frequencyScale.sourceID, "Leipzig.deu_news_2025_1M")

        let summary = VocabularyDocumentLemmaSummary(
            canonicalKey: "develop",
            displayLemma: "develop",
            observedForms: [VocabularyDocumentObservedForm(surface: "developed", occurrenceCount: 1)],
            occurrenceCount: 1,
            representativeRange: VocabularyDocumentSourceRange(unitIndex: 0, utf16Location: 0, utf16Length: 7)
        )
        XCTAssertEqual(english.bestRank(for: summary), 484)
    }
    func testPinnedResourceHasExpectedRowsAndFrequencyOrdering() throws {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/LeafReaderApp/Resources/GermanFrequency/deu_news_2025_1M.sqlite")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let table = GermanFrequencyRankTable(databaseURLs: [url])
        XCTAssertEqual(table.rowCount(), 200_000)
        XCTAssertEqual(table.rank(for: "Der"), 1)
        XCTAssertEqual(table.rank(for: "die"), 2)
        XCTAssertEqual(table.rank(for: "Haus"), 365)
        XCTAssertLessThan(try XCTUnwrap(table.rank(for: "entwickeln")), try XCTUnwrap(table.rank(for: "entwickelte")))
        XCTAssertNil(table.rank(for: "not-a-real-german-corpus-token-xyz"))
    }

    func testBestRankUsesLemmaAndObservedInflections() {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/LeafReaderApp/Resources/GermanFrequency/deu_news_2025_1M.sqlite")
        let table = GermanFrequencyRankTable(databaseURLs: [url])

        XCTAssertEqual(table.bestRank(
            lemma: "missing",
            observedForms: [
                VocabularyDocumentObservedForm(surface: "entwickelte", occurrenceCount: 2),
                VocabularyDocumentObservedForm(surface: "entwickeln", occurrenceCount: 1)
            ]
        ), 1322)
    }
}
