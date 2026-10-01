import Foundation
import XCTest
import LeafReaderCore
@testable import LeafReaderApp

final class VocabularyFormLabelCacheXCTests: XCTestCase {
    func testCacheIsNamespacedByLanguageEvidenceAndRuleset() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WordRecordSQLiteStore(
            databaseURL: directory.appendingPathComponent("form-labels.sqlite")
        )

        XCTAssertTrue(store.saveVocabularyFormLabel(
            language: .english,
            evidenceIdentity: "provider-a",
            surfaceKey: "was",
            lemmaKey: "be",
            label: WordFormLabel.finiteVerb.rawValue,
            rulesetVersion: 1
        ))

        XCTAssertEqual(
            store.vocabularyFormLabel(
                language: .english,
                evidenceIdentity: "provider-a",
                surfaceKey: "was",
                lemmaKey: "be",
                rulesetVersion: 1
            )?.label,
            WordFormLabel.finiteVerb.rawValue
        )
        XCTAssertNil(store.vocabularyFormLabel(
            language: .german,
            evidenceIdentity: "provider-a",
            surfaceKey: "was",
            lemmaKey: "be",
            rulesetVersion: 1
        ))
        XCTAssertNil(store.vocabularyFormLabel(
            language: .english,
            evidenceIdentity: "provider-b",
            surfaceKey: "was",
            lemmaKey: "be",
            rulesetVersion: 1
        ))
        XCTAssertNil(store.vocabularyFormLabel(
            language: .english,
            evidenceIdentity: "provider-a",
            surfaceKey: "was",
            lemmaKey: "be",
            rulesetVersion: 2
        ))
    }

    func testCachedNilRoundTripsAsAHit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WordRecordSQLiteStore(
            databaseURL: directory.appendingPathComponent("form-labels.sqlite")
        )

        XCTAssertTrue(store.saveVocabularyFormLabel(
            language: .english,
            evidenceIdentity: "provider-a",
            surfaceKey: "bigger",
            lemmaKey: "big",
            label: nil,
            rulesetVersion: 1
        ))

        let hit = store.vocabularyFormLabel(
            language: .english,
            evidenceIdentity: "provider-a",
            surfaceKey: "bigger",
            lemmaKey: "big",
            rulesetVersion: 1
        )
        XCTAssertNotNil(hit)
        XCTAssertNil(hit?.label)
    }
}
