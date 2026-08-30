import Foundation
import XCTest
import LeafReaderCore

final class VocabularyValidationStudyDatasetXCTests: XCTestCase {
    func testConsentedDatasetValidatesAndContainsNoProductDocumentFields() throws {
        let dataset = ConsentedValidationStudyDataset(
            studyProtocolVersion: "pilot-v1",
            consentProtocolVersion: "consent-v1",
            explicitConsentRecorded: true,
            records: [record()]
        )

        XCTAssertNoThrow(try dataset.validate())
        let data = try JSONEncoder().encode(dataset)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("opaqueStudyDocumentID"))
        XCTAssertTrue(json.contains("randomizedAuditInclusionProbability"))
        XCTAssertFalse(json.contains("documentTitle"))
        XCTAssertFalse(json.contains("filePath"))
        XCTAssertFalse(json.contains("rawDocumentText"))
        XCTAssertFalse(json.contains("typedMeaning"))
        XCTAssertFalse(json.contains("account"))
    }

    func testParticipantAndDocumentMustRemainSplitDisjoint() {
        let participantLeak = ConsentedValidationStudyDataset(
            studyProtocolVersion: "pilot-v1",
            consentProtocolVersion: "consent-v1",
            explicitConsentRecorded: true,
            records: [
                record(participant: "p-1", document: "d-1", split: .training),
                record(participant: "p-1", document: "d-2", split: .confirmatory)
            ]
        )
        XCTAssertThrowsError(try participantLeak.validate()) {
            XCTAssertEqual($0 as? VocabularyValidationStudyDatasetError, .participantSplitLeakage)
        }

        let documentLeak = ConsentedValidationStudyDataset(
            studyProtocolVersion: "pilot-v1",
            consentProtocolVersion: "consent-v1",
            explicitConsentRecorded: true,
            records: [
                record(participant: "p-1", document: "d-1", split: .training),
                record(participant: "p-2", document: "d-1", split: .confirmatory)
            ]
        )
        XCTAssertThrowsError(try documentLeak.validate()) {
            XCTAssertEqual($0 as? VocabularyValidationStudyDatasetError, .documentSplitLeakage)
        }
    }

    func testRaterDisagreementRequiresMatchingAdjudication() {
        let dataset = ConsentedValidationStudyDataset(
            studyProtocolVersion: "pilot-v1",
            consentProtocolVersion: "consent-v1",
            explicitConsentRecorded: true,
            records: [record(
                criterion: .known,
                firstRater: .known,
                secondRater: .unknownOrPartial,
                adjudicated: nil
            )]
        )

        XCTAssertThrowsError(try dataset.validate()) {
            XCTAssertEqual($0 as? VocabularyValidationStudyDatasetError, .inconsistentCriterionLabels)
        }
    }

    func testDelayedRetestRequiresOpaqueLinkage() {
        let dataset = ConsentedValidationStudyDataset(
            studyProtocolVersion: "pilot-v1",
            consentProtocolVersion: "consent-v1",
            explicitConsentRecorded: true,
            records: [record(phase: .delayedRetest, delayedRetestLinkage: nil)]
        )

        XCTAssertThrowsError(try dataset.validate()) {
            XCTAssertEqual($0 as? VocabularyValidationStudyDatasetError, .missingDelayedRetestLinkage)
        }
    }

    private func record(
        participant: String = "p-1",
        document: String = "d-1",
        split: VocabularyValidationStudySplit = .training,
        phase: VocabularyValidationStudyPhase = .preReading,
        criterion: VocabularyValidationCriterionLabel = .known,
        firstRater: VocabularyValidationCriterionLabel = .known,
        secondRater: VocabularyValidationCriterionLabel = .known,
        adjudicated: VocabularyValidationCriterionLabel? = nil,
        delayedRetestLinkage: String? = nil
    ) -> VocabularyValidationStudyRecord {
        VocabularyValidationStudyRecord(
            participantPseudonym: participant,
            opaqueStudyDocumentID: document,
            languageCode: "en",
            lexicalItemID: VocabularyLexicalItemID(
                language: "en",
                lemma: "develop",
                partOfSpeech: .verb
            ),
            analysisSplit: split,
            phase: phase,
            criterionLabel: criterion,
            firstRaterLabel: firstRater,
            secondRaterLabel: secondRater,
            adjudicatedLabel: adjudicated,
            randomizedAuditInclusionProbability: 0.25,
            questionAssignment: VocabularyValidationQuestionAssignment(
                questionOrdinal: 15,
                selectionType: .tailValidation,
                predictedKnownBeforeAnswer: 0.9,
                thetaBinBeforeAnswer: "bin-7",
                assignmentPolicyVersion: "study-assignment-v1"
            ),
            delayedRetestLinkage: delayedRetestLinkage
        )
    }
}
