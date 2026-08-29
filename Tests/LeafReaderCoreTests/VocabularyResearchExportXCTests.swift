import Foundation
import XCTest
import LeafReaderCore

final class VocabularyResearchExportXCTests: XCTestCase {
    func testLocalResearchExportIsIdempotentAndOmitsSensitiveDocumentFields() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VocabularyResearchEvidenceStore(databaseURL: root.appendingPathComponent("personal-vocabulary.sqlite3"))
        let lexical = VocabularyLexicalItemID(language: "en", lemma: "develop", partOfSpeech: .verb)
        let candidate = DocumentVocabularyCandidate(
            canonicalKey: lexical.canonicalKey,
            displayLemma: "develop",
            lexicalItemID: lexical,
            partOfSpeech: .verb,
            observedForms: [VocabularyDocumentObservedForm(surface: "developed", occurrenceCount: 2)],
            occurrenceCount: 2,
            representativeRange: VocabularyDocumentSourceRange(unitIndex: 4, utf16Location: 50, utf16Length: 9),
            generalFrequencyRank: 484,
            difficultyPrior: VocabularyItemDifficultyPrior.frequencyRank(
                484,
                scale: VocabularyFrequencyScale(sourceID: "test", version: "v1", maximumRank: 47_062)
            )
        )
        let inventory = DocumentVocabularyInventory(
            languageCode: "en",
            candidates: [candidate],
            documentDomain: .literary
        )
        let answer = VocabularyAssessmentAnswer(
            canonicalKey: lexical.canonicalKey,
            evidence: .typedVerifiedKnown,
            typedMeaning: "sensitive typed response"
        )

        XCTAssertTrue(store.recordCompletedSession(
            contributionID: "session-a",
            inventory: inventory,
            answers: [answer],
            protocolVersion: 3
        ))
        XCTAssertTrue(store.recordCompletedSession(
            contributionID: "session-a",
            inventory: inventory,
            answers: [answer],
            protocolVersion: 3
        ))
        XCTAssertEqual(store.recordCount(), 1)

        let exported = store.export(profile: VocabularyResearchProfile(
            participantPseudonym: "lr-random",
            firstLanguageCode: "de",
            selfRatedProficiency: .b1B2
        ))
        XCTAssertEqual(exported.schemaVersion, 2)
        XCTAssertEqual(exported.records.count, 1)
        XCTAssertEqual(exported.records[0].lexicalItemID, lexical)
        XCTAssertEqual(exported.records[0].documentDomain, .literary)
        XCTAssertEqual(exported.records[0].sessionOrdinal, 1)
        let json = try XCTUnwrap(String(data: exported.encoded(), encoding: .utf8))
        XCTAssertFalse(json.contains("sensitive typed response"))
        XCTAssertFalse(json.contains("documentID"))
        XCTAssertFalse(json.contains("context"))
        XCTAssertFalse(json.contains("timestamp"))
        XCTAssertTrue(json.contains("B1/B2"))
    }

    func testOnlyReviewedEligibleRaschCalibrationItemsReachProductionMap() {
        let lexical = VocabularyLexicalItemID(language: "en", lemma: "develop", partOfSpeech: .verb)
        let eligible = VocabularyItemCalibrationPack.Item(
            lexicalItemID: lexical,
            difficulty: 0.4,
            standardError: 0.2,
            independentLearnerCount: 120,
            hasMaterialDIF: false
        )
        let unreviewed = VocabularyItemCalibrationPack(
            version: "test",
            reviewed: false,
            model: "rasch",
            items: [eligible]
        )
        XCTAssertTrue(unreviewed.productionItemsByKey.isEmpty)

        let reviewed = VocabularyItemCalibrationPack(
            version: "test",
            reviewed: true,
            model: "rasch",
            items: [eligible]
        )
        XCTAssertEqual(reviewed.productionItemsByKey[lexical.canonicalKey]?.difficulty, 0.4)
    }

    func testCalibrationLoaderRejectsUnreviewedPack() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let pack = VocabularyItemCalibrationPack(
            version: "tool-output",
            reviewed: false,
            model: "rasch",
            items: []
        )
        try JSONEncoder().encode(pack).write(to: url)
        XCTAssertNil(VocabularyItemCalibrationPackLoader.loadReviewed(languageCode: "en", resourceURLs: [url]))
    }
}
