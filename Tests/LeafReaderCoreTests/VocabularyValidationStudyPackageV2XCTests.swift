import Foundation
import XCTest
@testable import LeafReaderCore

final class VocabularyValidationStudyPackageV2XCTests: XCTestCase {
    func testFabricatedRelationalPackageValidatesAndRoundTripsWithoutPrivateFields() throws {
        let package = validPackage()
        XCTAssertNoThrow(try package.validate())
        let data = try JSONEncoder().encode(package)
        XCTAssertEqual(try JSONDecoder().decode(ConsentedValidationStudyPackageV2.self, from: data), package)
        let json = String(decoding: data, as: UTF8.self)
        for forbidden in ["documentTitle", "filePath", "rawDocumentText", "typedMeaning", "accountID"] {
            XCTAssertFalse(json.contains(forbidden))
        }
        XCTAssertTrue(json.contains("fabricated-rehearsal"))
        XCTAssertTrue(json.contains("provisional-not-approved"))
    }

    func testAmbiguousMissingAndDelayedRecordsRemainDistinct() throws {
        var package = validPackage()
        package = replacingCriteria(in: package, with: [
            criterion(status: .ambiguous, ambiguity: "multiple-context-free-senses"),
            criterion(phase: .immediatePostLearning, status: .missing, missing: "participant-declined"),
            criterion(phase: .delayedRetest, status: .known, retest: "retest-1")
        ])
        XCTAssertNoThrow(try package.validate())
    }

    func testBrokenInventoryNearDuplicateDeckAndRealCollectionAreRejected() {
        let package = validPackage()
        XCTAssertThrowsError(try copy(package, realCollectionAuthorized: true).validate())
        XCTAssertThrowsError(try copy(package, itemPredictions: []).validate()) {
            XCTAssertEqual($0 as? VocabularyValidationStudyPackageV2Error, .inventoryMismatch)
        }
        let leaked = package.documents + [VocabularyStudyDocumentV2(
            opaqueStudyDocumentID: "doc-confirmatory",
            nearDuplicateGroupID: "near-1",
            languageCode: "en",
            genre: "news",
            format: "epub",
            analysisSplit: .confirmatory,
            inventorySnapshotID: "inventory-2",
            eligibleLexicalItemCount: 1,
            eligibleOccurrenceMass: 10
        )]
        XCTAssertThrowsError(try copy(package, documents: leaked).validate()) {
            XCTAssertEqual($0 as? VocabularyValidationStudyPackageV2Error, .nearDuplicateLeakage)
        }
        let badDeck = package.deckSnapshots.map {
            VocabularyStudyDeckSnapshotV2(
                assessmentID: $0.assessmentID,
                snapshotID: $0.snapshotID,
                role: $0.role,
                inventorySnapshotID: $0.inventorySnapshotID,
                selectedLexicalItemIDs: [lexical("not-in-inventory")],
                targetCoverage: $0.targetCoverage,
                expectedCoverage: $0.expectedCoverage,
                conservativeCoverage: $0.conservativeCoverage
            )
        }
        XCTAssertThrowsError(try copy(package, deckSnapshots: badDeck).validate())
    }

    private func validPackage() -> ConsentedValidationStudyPackageV2 {
        let item = lexical("develop")
        return ConsentedValidationStudyPackageV2(
            schemaVersion: 2,
            dataRole: "fabricated-rehearsal",
            realCollectionAuthorized: false,
            studyProtocolVersion: "fabricated-v2",
            rubricVersion: "fabricated-rubric-v1",
            analysisConfigurationVersion: "provisional-analysis-v1",
            estimatorStatus: "provisional-not-approved",
            participants: [VocabularyStudyParticipantV2(
                participantPseudonym: "p-1", consentProtocolVersion: "fabricated-consent-v1",
                consentRecorded: true, languageCode: "en", l1LanguageCode: "de",
                proficiencyBand: "B1/B2", analysisSplit: .training, cohort: "fabricated"
            )],
            documents: [VocabularyStudyDocumentV2(
                opaqueStudyDocumentID: "doc-1", nearDuplicateGroupID: "near-1",
                languageCode: "en", genre: "news", format: "pdf", analysisSplit: .training,
                inventorySnapshotID: "inventory-1", eligibleLexicalItemCount: 1,
                eligibleOccurrenceMass: 10
            )],
            assessments: [VocabularyStudyAssessmentV2(
                assessmentID: "assessment-1", participantPseudonym: "p-1",
                opaqueStudyDocumentID: "doc-1", condition: .cold, algorithmVersion: 3,
                modelVersion: "model-v3", observationVersion: "categorical-evidence-v1",
                resourceVersion: "resource-v1", priorUsed: false, priorEligible: false,
                questionCount: 1, stopReason: "exhaustedCandidates", abandoned: false,
                lookupFailureCount: 0, expectedCurrentCoverage: 0.7,
                projectedCoverage: 1, conservativeCoverage: 0.98, sessionOrder: 1
            )],
            itemPredictions: [VocabularyStudyItemPredictionV2(
                assessmentID: "assessment-1", inventorySnapshotID: "inventory-1",
                lexicalItemID: item, finalKnownProbability: 0.7, occurrenceCount: 10,
                classification: .uncertain, status: .asked, evidence: .verifiedKnown
            )],
            criterionRecords: [criterion()],
            questionTraces: [VocabularyStudyQuestionTraceV2(
                assessmentID: "assessment-1", questionOrdinal: 1, lexicalItemID: item,
                evidence: .verifiedKnown, selectionType: .initialCalibration,
                predictedKnownBeforeAnswer: 0.5, revealedAfterResponse: true,
                elapsedMilliseconds: 120
            )],
            deckSnapshots: [VocabularyStudyDeckSnapshotV2(
                assessmentID: "assessment-1", snapshotID: "deck-1", role: .proposed,
                inventorySnapshotID: "inventory-1", selectedLexicalItemIDs: [item],
                targetCoverage: 0.98, expectedCoverage: 1, conservativeCoverage: 0.98
            )],
            samplingManifests: [VocabularyStudySamplingManifestV2(
                samplingStageID: "sample-1", opaqueStudyDocumentID: "doc-1",
                frameHash: "frame-hash", designVersion: "census-v1", seed: 1,
                census: true, minimumInclusionProbability: 1, maximumDesignWeight: 1,
                weightBasedEffectiveSampleSize: 1, expectedSelectedCardSupport: 1,
                expectedFinalTailSupport: 1
            )],
            retestManifests: [VocabularyStudyRetestManifestV2(
                retestLinkageID: "retest-1", assessmentID: "assessment-1",
                elapsedHours: 168, windowVersion: "week-1", missingnessStatus: "observed"
            )]
        )
    }

    private func criterion(
        phase: VocabularyValidationStudyPhase = .preReading,
        status: VocabularyStudyCriterionStatusV2 = .known,
        ambiguity: String? = nil,
        missing: String? = nil,
        retest: String? = nil
    ) -> VocabularyStudyCriterionRecordV2 {
        VocabularyStudyCriterionRecordV2(
            assessmentID: "assessment-1", lexicalItemID: lexical("develop"), phase: phase,
            collectedBeforeReveal: phase == .preReading,
            status: status, firstRaterStatus: status == .missing ? nil : .known,
            secondRaterStatus: status == .missing ? nil : .known,
            adjudicatedStatus: status == .ambiguous ? .ambiguous : nil,
            ambiguityReason: ambiguity, missingnessReason: missing,
            rubricVersion: "fabricated-rubric-v1", samplingStageID: "sample-1",
            inclusionProbability: 1, retestLinkageID: retest
        )
    }

    private func lexical(_ lemma: String) -> VocabularyLexicalItemID {
        VocabularyLexicalItemID(language: "en", lemma: lemma, partOfSpeech: .verb)
    }

    private func replacingCriteria(
        in package: ConsentedValidationStudyPackageV2,
        with records: [VocabularyStudyCriterionRecordV2]
    ) -> ConsentedValidationStudyPackageV2 { copy(package, criterionRecords: records) }

    private func copy(
        _ package: ConsentedValidationStudyPackageV2,
        realCollectionAuthorized: Bool? = nil,
        documents: [VocabularyStudyDocumentV2]? = nil,
        itemPredictions: [VocabularyStudyItemPredictionV2]? = nil,
        criterionRecords: [VocabularyStudyCriterionRecordV2]? = nil,
        deckSnapshots: [VocabularyStudyDeckSnapshotV2]? = nil
    ) -> ConsentedValidationStudyPackageV2 {
        ConsentedValidationStudyPackageV2(
            schemaVersion: package.schemaVersion, dataRole: package.dataRole,
            realCollectionAuthorized: realCollectionAuthorized ?? package.realCollectionAuthorized,
            studyProtocolVersion: package.studyProtocolVersion, rubricVersion: package.rubricVersion,
            analysisConfigurationVersion: package.analysisConfigurationVersion,
            estimatorStatus: package.estimatorStatus, participants: package.participants,
            documents: documents ?? package.documents, assessments: package.assessments,
            itemPredictions: itemPredictions ?? package.itemPredictions,
            criterionRecords: criterionRecords ?? package.criterionRecords,
            questionTraces: package.questionTraces,
            deckSnapshots: deckSnapshots ?? package.deckSnapshots,
            samplingManifests: package.samplingManifests,
            retestManifests: package.retestManifests
        )
    }
}
