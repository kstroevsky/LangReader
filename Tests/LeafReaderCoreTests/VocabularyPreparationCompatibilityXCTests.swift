import XCTest
@testable import LeafReaderCore

final class VocabularyPreparationCompatibilityXCTests: XCTestCase {
    func testFingerprintCanonicalizesProviderAndDegradedModeOrdering() throws {
        let first = try makeFingerprint(
            linguisticProviders: [provider("linguistic.b"), provider("linguistic.a")],
            degradedModes: ["definitions-unavailable", "frequency-fallback"]
        )
        let second = try makeFingerprint(
            linguisticProviders: [provider("linguistic.a"), provider("linguistic.b")],
            degradedModes: ["frequency-fallback", "definitions-unavailable"]
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.stableDigest, second.stableDigest)
    }

    func testFingerprintChangesWhenConsumedSemanticInputsChange() throws {
        let baseline = try makeFingerprint()
        let variants = try [
            makeFingerprint(language: "de"),
            makeFingerprint(languageProfileVersion: "profile-v2"),
            makeFingerprint(lexicalPolicyVersion: "lexical-v2"),
            makeFingerprint(linguisticProviders: [provider("linguistic.a", version: "2")]),
            makeFingerprint(linguisticRuntimeSignature: "runtime-v2"),
            makeFingerprint(difficultyProviderVersion: "2"),
            makeFingerprint(calibrationPackIDAndVersion: "pack-a@2"),
            makeFingerprint(definitionProviderVersion: "2"),
            makeFingerprint(normalizationVersion: "normalization-v2"),
            makeFingerprint(assessmentPolicyVersion: "assessment-v2"),
            makeFingerprint(degradedModes: ["definitions-unavailable"])
        ]

        for variant in variants {
            XCTAssertNotEqual(variant, baseline)
            XCTAssertNotEqual(variant.stableDigest, baseline.stableDigest)
        }
    }

    func testStateIdentitiesBindDocumentTextAndCompleteInventory() throws {
        let firstText = VocabularyPreparationStateIdentity.text(
            documentID: "document-a",
            texts: ["one", "two"]
        )
        XCTAssertEqual(
            firstText,
            VocabularyPreparationStateIdentity.text(documentID: "document-a", texts: ["one", "two"])
        )
        XCTAssertNotEqual(
            firstText,
            VocabularyPreparationStateIdentity.text(documentID: "document-b", texts: ["one", "two"])
        )
        XCTAssertNotEqual(
            firstText,
            VocabularyPreparationStateIdentity.text(documentID: "document-a", texts: ["one", "changed"])
        )

        let language = try XCTUnwrap(VocabularyLanguageID("en"))
        let lexical = VocabularyLexicalItemID(language: language, lemma: "example", partOfSpeech: .noun)
        let firstInventory = DocumentVocabularyInventory(
            languageCode: language.bcp47,
            candidates: [
                DocumentVocabularyCandidate(
                    canonicalKey: lexical.canonicalKey,
                    displayLemma: "example",
                    lexicalItemID: lexical,
                    partOfSpeech: .noun,
                    observedForms: [VocabularyDocumentObservedForm(surface: "example", occurrenceCount: 2)],
                    occurrenceCount: 2,
                    representativeRange: VocabularyDocumentSourceRange(unitIndex: 0, utf16Location: 0, utf16Length: 7),
                    generalFrequencyRank: 100,
                    difficulty: 0.25
                )
            ]
        )
        var changedCandidates = firstInventory.candidates
        changedCandidates[0] = DocumentVocabularyCandidate(
            canonicalKey: lexical.canonicalKey,
            displayLemma: "example",
            lexicalItemID: lexical,
            partOfSpeech: .noun,
            observedForms: [VocabularyDocumentObservedForm(surface: "example", occurrenceCount: 3)],
            occurrenceCount: 3,
            representativeRange: VocabularyDocumentSourceRange(unitIndex: 0, utf16Location: 0, utf16Length: 7),
            generalFrequencyRank: 100,
            difficulty: 0.25
        )
        let changedInventory = DocumentVocabularyInventory(
            languageCode: language.bcp47,
            candidates: changedCandidates
        )

        XCTAssertEqual(
            VocabularyPreparationStateIdentity.inventory(firstInventory),
            VocabularyPreparationStateIdentity.inventory(firstInventory)
        )
        XCTAssertNotEqual(
            VocabularyPreparationStateIdentity.inventory(firstInventory),
            VocabularyPreparationStateIdentity.inventory(changedInventory)
        )
    }

    private func makeFingerprint(
        language: String = "en",
        languageProfileVersion: String = "profile-v1",
        lexicalPolicyVersion: String = "lexical-v1",
        linguisticProviders: [VocabularySemanticProviderIdentity]? = nil,
        linguisticRuntimeSignature: String = "runtime-v1",
        difficultyProviderVersion: String = "1",
        calibrationPackIDAndVersion: String? = "pack-a@1",
        definitionProviderVersion: String = "1",
        normalizationVersion: String = "normalization-v1",
        assessmentPolicyVersion: String = "assessment-v1",
        degradedModes: [String] = []
    ) throws -> VocabularyPreparationCompatibilityFingerprint {
        VocabularyPreparationCompatibilityFingerprint(
            algorithmVersion: 8,
            language: try XCTUnwrap(VocabularyLanguageID(language)),
            languageProfileVersion: languageProfileVersion,
            lexicalPolicyVersion: lexicalPolicyVersion,
            linguisticProviders: linguisticProviders ?? [provider("linguistic.a")],
            linguisticRuntimeSignature: linguisticRuntimeSignature,
            difficultyProvider: VocabularyDifficultyProviderSemanticIdentity(
                providerID: "difficulty.a",
                providerVersion: difficultyProviderVersion,
                calibrationPackIDAndVersion: calibrationPackIDAndVersion
            ),
            definitionProvider: provider("definition.a", version: definitionProviderVersion),
            normalizationVersion: normalizationVersion,
            assessmentPolicyVersion: assessmentPolicyVersion,
            degradedModes: degradedModes
        )
    }

    private func provider(
        _ id: String,
        version: String = "1"
    ) -> VocabularySemanticProviderIdentity {
        VocabularySemanticProviderIdentity(
            id: id,
            version: version,
            normalizationVersion: "normalization-v1"
        )
    }
}
