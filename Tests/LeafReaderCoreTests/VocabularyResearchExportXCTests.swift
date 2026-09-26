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
            typedMeaning: "sensitive typed response",
            questionOrdinal: 15,
            selectionType: .tailValidation,
            predictedKnownBeforeAnswer: 0.91
        )
        let compatibility = try compatibilityFingerprint()

        XCTAssertTrue(store.recordCompletedSession(
            contributionID: "session-a",
            inventory: inventory,
            answers: [answer],
            protocolVersion: 3,
            compatibilityFingerprint: compatibility
        ))
        XCTAssertTrue(store.recordCompletedSession(
            contributionID: "session-a",
            inventory: inventory,
            answers: [answer],
            protocolVersion: 3,
            compatibilityFingerprint: compatibility
        ))
        XCTAssertEqual(store.recordCount(), 1)

        let exported = store.export(profile: VocabularyResearchProfile(
            participantPseudonym: "lr-random",
            firstLanguageCode: "de",
            selfRatedProficiency: .b1B2
        ))
        XCTAssertEqual(exported.schemaVersion, 3)
        XCTAssertEqual(exported.records.count, 1)
        XCTAssertEqual(exported.records[0].lexicalItemID, lexical)
        XCTAssertEqual(exported.records[0].documentDomain, .literary)
        XCTAssertEqual(exported.records[0].sessionOrdinal, 1)
        XCTAssertEqual(exported.records[0].compatibilityFingerprint, compatibility)
        XCTAssertEqual(exported.records[0].compatibilityFingerprintDigest, compatibility.stableDigest)
        let json = try XCTUnwrap(String(data: exported.encoded(), encoding: .utf8))
        XCTAssertFalse(json.contains("sensitive typed response"))
        XCTAssertFalse(json.contains("documentID"))
        XCTAssertFalse(json.contains("context"))
        XCTAssertFalse(json.contains("timestamp"))
        XCTAssertFalse(json.contains("questionOrdinal"))
        XCTAssertFalse(json.contains("selectionType"))
        XCTAssertFalse(json.contains("predictedKnownBeforeAnswer"))
        XCTAssertTrue(json.contains("B1/B2"))
    }

    func testOnlyReviewedCompatibleEligibleRaschCalibrationItemsReachProductionMap() throws {
        let lexical = VocabularyLexicalItemID(language: "en", lemma: "develop", partOfSpeech: .verb)
        let target = try compatibilityFingerprint().calibrationTarget
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
            target: target,
            observationCompatibilityFingerprintDigest: "observations-v1",
            items: [eligible]
        )
        XCTAssertTrue(unreviewed.productionItemsByKey.isEmpty)

        let reviewed = VocabularyItemCalibrationPack(
            version: "test",
            reviewed: true,
            model: "rasch",
            target: target,
            observationCompatibilityFingerprintDigest: "observations-v1",
            items: [eligible]
        )
        XCTAssertEqual(reviewed.productionItemsByKey[lexical.canonicalKey]?.difficulty, 0.4)
    }

    func testDirectEvidenceCandidateIsNotExportedAsResolvedLexicalEvidence() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VocabularyResearchEvidenceStore(
            databaseURL: root.appendingPathComponent("personal-vocabulary.sqlite3")
        )
        let candidate = DocumentVocabularyCandidate(
            canonicalKey: "anchor|en|lemma|record",
            lemmaKey: "record",
            displayLemma: "record",
            lexicalItemID: nil,
            partOfSpeech: .unknown,
            identityPolicy: .directEvidenceOnly,
            observedForms: [VocabularyDocumentObservedForm(surface: "record", occurrenceCount: 1)],
            occurrenceCount: 1,
            representativeRange: VocabularyDocumentSourceRange(
                unitIndex: 0,
                utf16Location: 0,
                utf16Length: 6
            ),
            generalFrequencyRank: nil,
            difficulty: 0
        )
        let inventory = DocumentVocabularyInventory(
            languageCode: "en",
            candidates: [candidate]
        )

        XCTAssertTrue(store.recordCompletedSession(
            contributionID: "direct-evidence-only",
            inventory: inventory,
            answers: [VocabularyAssessmentAnswer(
                canonicalKey: candidate.canonicalKey,
                evidence: .reportedUnknown
            )],
            protocolVersion: 4
        ))
        XCTAssertEqual(store.recordCount(), 0)
        XCTAssertTrue(store.export(profile: VocabularyResearchProfile(
            participantPseudonym: "lr-direct",
            firstLanguageCode: "de",
            selfRatedProficiency: .b1B2
        )).records.isEmpty)
    }

    func testCalibrationLoaderRejectsUnreviewedPack() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let pack = VocabularyItemCalibrationPack(
            version: "tool-output",
            reviewed: false,
            model: "rasch",
            target: try compatibilityFingerprint().calibrationTarget,
            observationCompatibilityFingerprintDigest: "observations-v1",
            items: []
        )
        try JSONEncoder().encode(pack).write(to: url)
        XCTAssertNil(VocabularyItemCalibrationPackLoader.loadReviewed(
            target: try compatibilityFingerprint().calibrationTarget,
            resourceURLs: [url]
        ))
    }

    func testCalibrationLoaderRejectsLegacyWrongTargetAndInvalidItems() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let target = try compatibilityFingerprint().calibrationTarget
        let lexical = VocabularyLexicalItemID(language: "en", lemma: "develop", partOfSpeech: .verb)
        let eligible = VocabularyItemCalibrationPack.Item(
            lexicalItemID: lexical,
            difficulty: 0.4,
            standardError: 0.2,
            independentLearnerCount: 120,
            hasMaterialDIF: false
        )

        let legacy = VocabularyItemCalibrationPack(
            version: "legacy",
            reviewed: true,
            model: "rasch",
            items: [eligible]
        )
        try JSONEncoder().encode(legacy).write(to: url)
        XCTAssertNil(VocabularyItemCalibrationPackLoader.loadReviewed(target: target, resourceURLs: [url]))

        let wrongTarget = try VocabularyCalibrationCompatibilityTarget(
            language: XCTUnwrap(VocabularyLanguageID("en")),
            languageProfileVersion: "other-profile",
            linguisticProviders: target.linguisticProviders,
            linguisticRuntimeSignature: target.linguisticRuntimeSignature,
            difficultyProvider: VocabularyDifficultyProviderSemanticIdentity(
                providerID: target.difficultyProviderID,
                providerVersion: target.difficultyProviderVersion
            ),
            normalizationVersion: target.normalizationVersion,
            assessmentPolicyVersion: target.assessmentPolicyVersion
        )
        let wrong = VocabularyItemCalibrationPack(
            version: "wrong-target",
            reviewed: true,
            model: "rasch",
            target: wrongTarget,
            observationCompatibilityFingerprintDigest: "observations-v1",
            items: [eligible]
        )
        try JSONEncoder().encode(wrong).write(to: url)
        XCTAssertNil(VocabularyItemCalibrationPackLoader.loadReviewed(target: target, resourceURLs: [url]))

        let duplicate = VocabularyItemCalibrationPack(
            version: "duplicate",
            reviewed: true,
            model: "rasch",
            target: target,
            observationCompatibilityFingerprintDigest: "observations-v1",
            items: [eligible, eligible]
        )
        try JSONEncoder().encode(duplicate).write(to: url)
        XCTAssertNil(VocabularyItemCalibrationPackLoader.loadReviewed(target: target, resourceURLs: [url]))

        let wrongLanguageItem = VocabularyItemCalibrationPack.Item(
            lexicalItemID: VocabularyLexicalItemID(language: "de", lemma: "entwickeln", partOfSpeech: .verb),
            difficulty: 0.4,
            standardError: 0.2,
            independentLearnerCount: 120,
            hasMaterialDIF: false
        )
        let wrongLanguage = VocabularyItemCalibrationPack(
            version: "wrong-language",
            reviewed: true,
            model: "rasch",
            target: target,
            observationCompatibilityFingerprintDigest: "observations-v1",
            items: [wrongLanguageItem]
        )
        try JSONEncoder().encode(wrongLanguage).write(to: url)
        XCTAssertNil(VocabularyItemCalibrationPackLoader.loadReviewed(target: target, resourceURLs: [url]))

        let invalidNumeric = VocabularyItemCalibrationPack(
            version: "invalid-numeric",
            reviewed: true,
            model: "rasch",
            target: target,
            observationCompatibilityFingerprintDigest: "observations-v1",
            items: [VocabularyItemCalibrationPack.Item(
                lexicalItemID: lexical,
                difficulty: .infinity,
                standardError: 0.2,
                independentLearnerCount: 120,
                hasMaterialDIF: false
            )]
        )
        XCTAssertTrue(invalidNumeric.productionItemsByKey.isEmpty)
    }

    private func compatibilityFingerprint() throws -> VocabularyPreparationCompatibilityFingerprint {
        VocabularyPreparationCompatibilityFingerprint(
            algorithmVersion: VocabularyPreparationSession.currentAlgorithmVersion,
            language: try XCTUnwrap(VocabularyLanguageID("en")),
            languageProfileVersion: "en-profile-v1",
            linguisticProviders: [VocabularyLinguisticCacheIdentity.builtInProvider],
            linguisticRuntimeSignature: "test-runtime",
            difficultyProvider: VocabularyDifficultyProviderSemanticIdentity(
                providerID: "difficulty.ECDICT.frq",
                providerVersion: "bundled-lite-v1"
            ),
            definitionProvider: VocabularySemanticProviderIdentity(
                id: "definition.test",
                version: "1",
                normalizationVersion: VocabularyNormalizationPolicy.currentVersion
            )
        )
    }
}
