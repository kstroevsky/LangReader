import Foundation
import XCTest
import LeafReaderCore
@testable import LeafReaderApp

@MainActor
final class VocabularySettingsModelXCTests: XCTestCase {
    func testPreviewAndExplicitSaveContainOnlyDisclosedResearchFields() throws {
        let saver = FakeVocabularyResearchExportSaver()
        let suiteName = "VocabularySettingsModelXCTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let model = VocabularySettingsModel(
            store: EmptyVocabularyReaderPriorStore(),
            researchStore: FixtureVocabularyResearchEvidenceStore(),
            researchExportSaver: saver,
            preferences: preferences
        )
        model.firstLanguageCode = "de"
        model.selfRatedProficiency = "intermediate"

        model.previewResearchExport()
        XCTAssertTrue(model.researchPreview.contains("develop"))
        for forbidden in ["documentID", "document title", "file path", "context", "definition", "typed meaning", "timestamp"] {
            XCTAssertFalse(model.researchPreview.localizedCaseInsensitiveContains(forbidden), forbidden)
        }

        model.saveResearchExport()
        let saved = try XCTUnwrap(saver.savedData)
        XCTAssertEqual(saver.suggestedFilename, "leafreader-vocabulary-research.json")
        let decoded = try JSONDecoder().decode(VocabularyResearchExport.self, from: saved)
        XCTAssertEqual(decoded.participant.firstLanguageCode, "de")
        XCTAssertEqual(decoded.participant.selfRatedProficiency, "intermediate")
        XCTAssertEqual(decoded.records.count, 1)
    }

    func testPseudonymResetChangesOnlyLocalPseudonym() throws {
        let suiteName = "VocabularySettingsModelXCTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let model = VocabularySettingsModel(
            store: EmptyVocabularyReaderPriorStore(),
            researchStore: FixtureVocabularyResearchEvidenceStore(),
            researchExportSaver: FakeVocabularyResearchExportSaver(),
            preferences: preferences
        )
        let first = model.participantPseudonym

        model.resetPseudonym()

        XCTAssertNotEqual(model.participantPseudonym, first)
        XCTAssertTrue(model.participantPseudonym.hasPrefix("lr-"))
    }
}

@MainActor
private final class FakeVocabularyResearchExportSaver: VocabularyResearchExportSaving {
    private(set) var savedData: Data?
    private(set) var suggestedFilename: String?

    func save(_ data: Data, suggestedFilename: String) throws -> Bool {
        savedData = data
        self.suggestedFilename = suggestedFilename
        return true
    }
}

private struct EmptyVocabularyReaderPriorStore: VocabularyReaderPriorStoring {
    func load(languageCode: String) -> VocabularyReaderPrior? { nil }
    func summaries() -> [VocabularyReaderPriorSummary] { [] }
    func recordCompletedSession(
        contributionID: String,
        languageCode: String,
        thetaPosterior: [Double],
        verifiedEvidenceCount: Int,
        completedAt: Date,
        algorithmVersion: Int
    ) -> Bool { true }
    func reset(languageCode: String) -> Bool { true }
}

private struct FixtureVocabularyResearchEvidenceStore: VocabularyResearchEvidenceStoring {
    func recordCompletedSession(
        contributionID: String,
        inventory: DocumentVocabularyInventory,
        answers: [VocabularyAssessmentAnswer],
        protocolVersion: Int
    ) -> Bool { true }

    func export(profile: VocabularyResearchProfile) -> VocabularyResearchExport {
        VocabularyResearchExport(
            participant: profile,
            records: [
                VocabularyResearchEvidenceRecord(
                    languageCode: "en",
                    lexicalItemID: VocabularyLexicalItemID(
                        language: "en",
                        lemma: "develop",
                        partOfSpeech: .verb
                    ),
                    documentDomain: .general,
                    difficultyMean: -0.4,
                    difficultyStandardDeviation: 0.5,
                    difficultySource: .rankedFrequency,
                    difficultyVersion: "fixture-v1",
                    evidence: .verifiedKnown,
                    protocolVersion: 3,
                    sessionOrdinal: 1
                )
            ]
        )
    }

    func recordCount() -> Int { 1 }
}
