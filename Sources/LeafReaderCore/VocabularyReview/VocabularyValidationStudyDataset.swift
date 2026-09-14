import Foundation

package enum VocabularyValidationStudySplit: String, Codable, Equatable, Sendable {
    case training
    case validation
    case confirmatory
}

package enum VocabularyValidationStudyPhase: String, Codable, Equatable, Sendable {
    case preReading
    case immediatePostLearning
    case delayedRetest
}

package enum VocabularyValidationCriterionLabel: String, Codable, Equatable, Sendable {
    case known
    case unknownOrPartial
}

package struct VocabularyValidationQuestionAssignment: Codable, Equatable, Sendable {
    package let questionOrdinal: Int
    package let selectionType: VocabularyQuestionSelectionType
    package let predictedKnownBeforeAnswer: Double
    package let thetaBinBeforeAnswer: String
    package let assignmentPolicyVersion: String

    package init(
        questionOrdinal: Int,
        selectionType: VocabularyQuestionSelectionType,
        predictedKnownBeforeAnswer: Double,
        thetaBinBeforeAnswer: String,
        assignmentPolicyVersion: String
    ) {
        self.questionOrdinal = questionOrdinal
        self.selectionType = selectionType
        self.predictedKnownBeforeAnswer = predictedKnownBeforeAnswer
        self.thetaBinBeforeAnswer = thetaBinBeforeAnswer
        self.assignmentPolicyVersion = assignmentPolicyVersion
    }
}

package struct VocabularyValidationStudyRecord: Codable, Equatable, Sendable {
    package let participantPseudonym: String
    package let opaqueStudyDocumentID: String
    package let languageCode: String
    package let lexicalItemID: VocabularyLexicalItemID
    package let analysisSplit: VocabularyValidationStudySplit
    package let phase: VocabularyValidationStudyPhase
    package let criterionLabel: VocabularyValidationCriterionLabel
    package let firstRaterLabel: VocabularyValidationCriterionLabel
    package let secondRaterLabel: VocabularyValidationCriterionLabel
    package let adjudicatedLabel: VocabularyValidationCriterionLabel?
    package let randomizedAuditInclusionProbability: Double
    package let questionAssignment: VocabularyValidationQuestionAssignment?
    package let delayedRetestLinkage: String?

    package init(
        participantPseudonym: String,
        opaqueStudyDocumentID: String,
        languageCode: String,
        lexicalItemID: VocabularyLexicalItemID,
        analysisSplit: VocabularyValidationStudySplit,
        phase: VocabularyValidationStudyPhase,
        criterionLabel: VocabularyValidationCriterionLabel,
        firstRaterLabel: VocabularyValidationCriterionLabel,
        secondRaterLabel: VocabularyValidationCriterionLabel,
        adjudicatedLabel: VocabularyValidationCriterionLabel? = nil,
        randomizedAuditInclusionProbability: Double,
        questionAssignment: VocabularyValidationQuestionAssignment? = nil,
        delayedRetestLinkage: String? = nil
    ) {
        self.participantPseudonym = participantPseudonym
        self.opaqueStudyDocumentID = opaqueStudyDocumentID
        self.languageCode = languageCode
        self.lexicalItemID = lexicalItemID
        self.analysisSplit = analysisSplit
        self.phase = phase
        self.criterionLabel = criterionLabel
        self.firstRaterLabel = firstRaterLabel
        self.secondRaterLabel = secondRaterLabel
        self.adjudicatedLabel = adjudicatedLabel
        self.randomizedAuditInclusionProbability = randomizedAuditInclusionProbability
        self.questionAssignment = questionAssignment
        self.delayedRetestLinkage = delayedRetestLinkage
    }
}

package enum VocabularyValidationStudyDatasetError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case missingProtocolVersion
    case consentNotRecorded
    case emptyIdentifier
    case invalidInclusionProbability
    case invalidQuestionAssignment
    case inconsistentCriterionLabels
    case missingDelayedRetestLinkage
    case duplicateRecord
    case participantSplitLeakage
    case documentSplitLeakage
}

/// Explicit-consent research data. This is intentionally separate from the
/// privacy-minimized product research export and is never populated by normal
/// Prepare Vocabulary sessions.
package struct ConsentedValidationStudyDataset: Codable, Equatable, Sendable {
    package static let currentSchemaVersion = 1

    package let schemaVersion: Int
    package let studyProtocolVersion: String
    package let consentProtocolVersion: String
    package let explicitConsentRecorded: Bool
    package let records: [VocabularyValidationStudyRecord]

    package init(
        schemaVersion: Int = currentSchemaVersion,
        studyProtocolVersion: String,
        consentProtocolVersion: String,
        explicitConsentRecorded: Bool,
        records: [VocabularyValidationStudyRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.studyProtocolVersion = studyProtocolVersion
        self.consentProtocolVersion = consentProtocolVersion
        self.explicitConsentRecorded = explicitConsentRecorded
        self.records = records
    }

    package func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw VocabularyValidationStudyDatasetError.unsupportedSchemaVersion(schemaVersion)
        }
        guard !studyProtocolVersion.trimmed.isEmpty,
              !consentProtocolVersion.trimmed.isEmpty else {
            throw VocabularyValidationStudyDatasetError.missingProtocolVersion
        }
        guard explicitConsentRecorded else {
            throw VocabularyValidationStudyDatasetError.consentNotRecorded
        }

        var participantSplits: [String: VocabularyValidationStudySplit] = [:]
        var documentSplits: [String: VocabularyValidationStudySplit] = [:]
        var recordKeys = Set<String>()
        for record in records {
            let participant = record.participantPseudonym.trimmed
            let document = record.opaqueStudyDocumentID.trimmed
            let language = record.languageCode.trimmed
            guard !participant.isEmpty, !document.isEmpty, !language.isEmpty else {
                throw VocabularyValidationStudyDatasetError.emptyIdentifier
            }
            guard record.randomizedAuditInclusionProbability > 0,
                  record.randomizedAuditInclusionProbability <= 1 else {
                throw VocabularyValidationStudyDatasetError.invalidInclusionProbability
            }
            if let assignment = record.questionAssignment {
                guard assignment.questionOrdinal > 0,
                      (0...1).contains(assignment.predictedKnownBeforeAnswer),
                      !assignment.thetaBinBeforeAnswer.trimmed.isEmpty,
                      !assignment.assignmentPolicyVersion.trimmed.isEmpty else {
                    throw VocabularyValidationStudyDatasetError.invalidQuestionAssignment
                }
            }
            let expectedCriterion: VocabularyValidationCriterionLabel
            if record.firstRaterLabel == record.secondRaterLabel {
                expectedCriterion = record.adjudicatedLabel ?? record.firstRaterLabel
            } else if let adjudicated = record.adjudicatedLabel {
                expectedCriterion = adjudicated
            } else {
                throw VocabularyValidationStudyDatasetError.inconsistentCriterionLabels
            }
            guard record.criterionLabel == expectedCriterion else {
                throw VocabularyValidationStudyDatasetError.inconsistentCriterionLabels
            }
            if record.phase == .delayedRetest,
               record.delayedRetestLinkage?.trimmed.isEmpty != false {
                throw VocabularyValidationStudyDatasetError.missingDelayedRetestLinkage
            }

            let recordKey = [
                participant,
                document,
                record.lexicalItemID.canonicalKey,
                record.phase.rawValue,
                record.delayedRetestLinkage?.trimmed ?? ""
            ].joined(separator: "|")
            guard recordKeys.insert(recordKey).inserted else {
                throw VocabularyValidationStudyDatasetError.duplicateRecord
            }
            if let existing = participantSplits[participant], existing != record.analysisSplit {
                throw VocabularyValidationStudyDatasetError.participantSplitLeakage
            }
            participantSplits[participant] = record.analysisSplit
            if let existing = documentSplits[document], existing != record.analysisSplit {
                throw VocabularyValidationStudyDatasetError.documentSplitLeakage
            }
            documentSplits[document] = record.analysisSplit
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
