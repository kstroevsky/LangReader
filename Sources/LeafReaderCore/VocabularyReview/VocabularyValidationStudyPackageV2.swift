import Foundation

package enum VocabularyStudyCriterionStatusV2: String, Codable, Equatable, Sendable {
    case known
    case unknownOrPartial
    case ambiguous
    case missing
}

package enum VocabularyStudyAssessmentConditionV2: String, Codable, Equatable, Sendable {
    case cold
    case warm
}

package enum VocabularyStudyItemStatusV2: String, Codable, Equatable, Sendable {
    case asked
    case unasked
    case skipped
    case excluded
}

package enum VocabularyStudyDeckRoleV2: String, Codable, Equatable, Sendable {
    case proposed
    case edited
}

package struct VocabularyStudyParticipantV2: Codable, Equatable, Sendable {
    package let participantPseudonym: String
    package let consentProtocolVersion: String
    package let consentRecorded: Bool
    package let languageCode: String
    package let l1LanguageCode: String?
    package let proficiencyBand: String
    package let analysisSplit: VocabularyValidationStudySplit
    package let cohort: String
}

package struct VocabularyStudyDocumentV2: Codable, Equatable, Sendable {
    package let opaqueStudyDocumentID: String
    package let nearDuplicateGroupID: String
    package let languageCode: String
    package let genre: String
    package let format: String
    package let analysisSplit: VocabularyValidationStudySplit
    package let inventorySnapshotID: String
    package let eligibleLexicalItemCount: Int
    package let eligibleOccurrenceMass: Int
}

package struct VocabularyStudyAssessmentV2: Codable, Equatable, Sendable {
    package let assessmentID: String
    package let participantPseudonym: String
    package let opaqueStudyDocumentID: String
    package let condition: VocabularyStudyAssessmentConditionV2
    package let algorithmVersion: Int
    package let modelVersion: String
    package let observationVersion: String
    package let resourceVersion: String
    package let priorUsed: Bool
    package let priorEligible: Bool
    package let questionCount: Int
    package let stopReason: String?
    package let abandoned: Bool
    package let lookupFailureCount: Int
    package let expectedCurrentCoverage: Double
    package let projectedCoverage: Double
    package let conservativeCoverage: Double
    package let sessionOrder: Int
}

package struct VocabularyStudyItemPredictionV2: Codable, Equatable, Sendable {
    package let assessmentID: String
    package let inventorySnapshotID: String
    package let lexicalItemID: VocabularyLexicalItemID
    package let finalKnownProbability: Double
    package let occurrenceCount: Int
    package let classification: VocabularyAssessmentClassification
    package let status: VocabularyStudyItemStatusV2
    package let evidence: VocabularyKnowledgeEvidence?
}

package struct VocabularyStudyCriterionRecordV2: Codable, Equatable, Sendable {
    package let assessmentID: String
    package let lexicalItemID: VocabularyLexicalItemID
    package let phase: VocabularyValidationStudyPhase
    package let collectedBeforeReveal: Bool
    package let status: VocabularyStudyCriterionStatusV2
    package let firstRaterStatus: VocabularyStudyCriterionStatusV2?
    package let secondRaterStatus: VocabularyStudyCriterionStatusV2?
    package let adjudicatedStatus: VocabularyStudyCriterionStatusV2?
    package let ambiguityReason: String?
    package let missingnessReason: String?
    package let rubricVersion: String
    package let samplingStageID: String
    package let inclusionProbability: Double
    package let retestLinkageID: String?
}

package struct VocabularyStudyQuestionTraceV2: Codable, Equatable, Sendable {
    package let assessmentID: String
    package let questionOrdinal: Int
    package let lexicalItemID: VocabularyLexicalItemID
    package let evidence: VocabularyKnowledgeEvidence
    package let selectionType: VocabularyQuestionSelectionType
    package let predictedKnownBeforeAnswer: Double
    package let revealedAfterResponse: Bool
    package let elapsedMilliseconds: Double
}

package struct VocabularyStudyDeckSnapshotV2: Codable, Equatable, Sendable {
    package let assessmentID: String
    package let snapshotID: String
    package let role: VocabularyStudyDeckRoleV2
    package let inventorySnapshotID: String
    package let selectedLexicalItemIDs: [VocabularyLexicalItemID]
    package let targetCoverage: Double
    package let expectedCoverage: Double
    package let conservativeCoverage: Double
}

package struct VocabularyStudySamplingManifestV2: Codable, Equatable, Sendable {
    package let samplingStageID: String
    package let opaqueStudyDocumentID: String
    package let frameHash: String
    package let designVersion: String
    package let seed: UInt64
    package let census: Bool
    package let minimumInclusionProbability: Double
    package let maximumDesignWeight: Double
    package let weightBasedEffectiveSampleSize: Double
    package let expectedSelectedCardSupport: Double
    package let expectedFinalTailSupport: Double
}

package struct VocabularyStudyRetestManifestV2: Codable, Equatable, Sendable {
    package let retestLinkageID: String
    package let assessmentID: String
    package let elapsedHours: Double
    package let windowVersion: String
    package let missingnessStatus: String
}

package enum VocabularyValidationStudyPackageV2Error: Error, Equatable, Sendable {
    case notFabricatedRehearsal
    case realCollectionNotAllowed
    case emptyIdentifier
    case duplicateIdentifier
    case brokenReference
    case splitLeakage
    case nearDuplicateLeakage
    case invalidProbability
    case invalidCount
    case inventoryMismatch
    case invalidCriterion
    case invalidQuestionTrace
    case invalidDeck
    case invalidSamplingDesign
    case invalidRetest
}

/// Additive fabricated-only relational package. Schema v1 remains unchanged.
package struct ConsentedValidationStudyPackageV2: Codable, Equatable, Sendable {
    package static let currentSchemaVersion = 2

    package let schemaVersion: Int
    package let dataRole: String
    package let realCollectionAuthorized: Bool
    package let studyProtocolVersion: String
    package let rubricVersion: String
    package let analysisConfigurationVersion: String
    package let estimatorStatus: String
    package let participants: [VocabularyStudyParticipantV2]
    package let documents: [VocabularyStudyDocumentV2]
    package let assessments: [VocabularyStudyAssessmentV2]
    package let itemPredictions: [VocabularyStudyItemPredictionV2]
    package let criterionRecords: [VocabularyStudyCriterionRecordV2]
    package let questionTraces: [VocabularyStudyQuestionTraceV2]
    package let deckSnapshots: [VocabularyStudyDeckSnapshotV2]
    package let samplingManifests: [VocabularyStudySamplingManifestV2]
    package let retestManifests: [VocabularyStudyRetestManifestV2]

    package func validate() throws {
        guard schemaVersion == 2, dataRole == "fabricated-rehearsal" else {
            throw VocabularyValidationStudyPackageV2Error.notFabricatedRehearsal
        }
        guard !realCollectionAuthorized else {
            throw VocabularyValidationStudyPackageV2Error.realCollectionNotAllowed
        }
        guard !studyProtocolVersion.trimmedV2.isEmpty,
              !rubricVersion.trimmedV2.isEmpty,
              !analysisConfigurationVersion.trimmedV2.isEmpty,
              estimatorStatus == "provisional-not-approved" else {
            throw VocabularyValidationStudyPackageV2Error.emptyIdentifier
        }
        try Self.unique(participants.map(\.participantPseudonym))
        try Self.unique(documents.map(\.opaqueStudyDocumentID))
        try Self.unique(assessments.map(\.assessmentID))
        try Self.unique(deckSnapshots.map(\.snapshotID))
        try Self.unique(samplingManifests.map(\.samplingStageID))
        try Self.unique(retestManifests.map(\.retestLinkageID))

        let participantByID = Dictionary(uniqueKeysWithValues: participants.map { ($0.participantPseudonym, $0) })
        let documentByID = Dictionary(uniqueKeysWithValues: documents.map { ($0.opaqueStudyDocumentID, $0) })
        let assessmentByID = Dictionary(uniqueKeysWithValues: assessments.map { ($0.assessmentID, $0) })
        let samplingIDs = Set(samplingManifests.map(\.samplingStageID))
        let retestIDs = Set(retestManifests.map(\.retestLinkageID))
        var participantSplits: [String: VocabularyValidationStudySplit] = [:]
        var documentSplits: [String: VocabularyValidationStudySplit] = [:]
        var nearDuplicateSplits: [String: VocabularyValidationStudySplit] = [:]
        for participant in participants {
            try Self.nonempty([participant.participantPseudonym, participant.consentProtocolVersion, participant.languageCode, participant.proficiencyBand, participant.cohort])
            guard participant.consentRecorded else { throw VocabularyValidationStudyPackageV2Error.brokenReference }
            participantSplits[participant.participantPseudonym] = participant.analysisSplit
        }
        for document in documents {
            try Self.nonempty([document.opaqueStudyDocumentID, document.nearDuplicateGroupID, document.languageCode, document.genre, document.format, document.inventorySnapshotID])
            guard document.eligibleLexicalItemCount > 0, document.eligibleOccurrenceMass > 0 else {
                throw VocabularyValidationStudyPackageV2Error.invalidCount
            }
            documentSplits[document.opaqueStudyDocumentID] = document.analysisSplit
            if let existing = nearDuplicateSplits[document.nearDuplicateGroupID], existing != document.analysisSplit {
                throw VocabularyValidationStudyPackageV2Error.nearDuplicateLeakage
            }
            nearDuplicateSplits[document.nearDuplicateGroupID] = document.analysisSplit
        }
        for assessment in assessments {
            guard let participant = participantByID[assessment.participantPseudonym],
                  let document = documentByID[assessment.opaqueStudyDocumentID] else {
                throw VocabularyValidationStudyPackageV2Error.brokenReference
            }
            guard participant.analysisSplit == document.analysisSplit else {
                throw VocabularyValidationStudyPackageV2Error.splitLeakage
            }
            guard assessment.questionCount >= 0, assessment.questionCount <= 80,
                  assessment.lookupFailureCount >= 0, assessment.sessionOrder > 0 else {
                throw VocabularyValidationStudyPackageV2Error.invalidCount
            }
            try Self.probabilities([assessment.expectedCurrentCoverage, assessment.projectedCoverage, assessment.conservativeCoverage])
        }
        var predictionKeys = Set<String>()
        for prediction in itemPredictions {
            guard let assessment = assessmentByID[prediction.assessmentID],
                  let document = documentByID[assessment.opaqueStudyDocumentID],
                  prediction.inventorySnapshotID == document.inventorySnapshotID else {
                throw VocabularyValidationStudyPackageV2Error.brokenReference
            }
            try Self.probabilities([prediction.finalKnownProbability])
            guard prediction.occurrenceCount > 0 else { throw VocabularyValidationStudyPackageV2Error.invalidCount }
            let key = prediction.assessmentID + "|" + prediction.lexicalItemID.canonicalKey
            guard predictionKeys.insert(key).inserted else { throw VocabularyValidationStudyPackageV2Error.duplicateIdentifier }
        }
        for assessment in assessments where !assessment.abandoned {
            guard let document = documentByID[assessment.opaqueStudyDocumentID] else { throw VocabularyValidationStudyPackageV2Error.brokenReference }
            let rows = itemPredictions.filter { $0.assessmentID == assessment.assessmentID && $0.status != .excluded }
            guard rows.count == document.eligibleLexicalItemCount,
                  rows.reduce(0, { $0 + $1.occurrenceCount }) == document.eligibleOccurrenceMass else {
                throw VocabularyValidationStudyPackageV2Error.inventoryMismatch
            }
        }
        var criterionKeys = Set<String>()
        for record in criterionRecords {
            guard assessmentByID[record.assessmentID] != nil, samplingIDs.contains(record.samplingStageID),
                  record.inclusionProbability > 0, record.inclusionProbability <= 1 else {
                throw VocabularyValidationStudyPackageV2Error.invalidCriterion
            }
            if record.status == .ambiguous, record.ambiguityReason?.trimmedV2.isEmpty != false {
                throw VocabularyValidationStudyPackageV2Error.invalidCriterion
            }
            if record.status == .missing, record.missingnessReason?.trimmedV2.isEmpty != false {
                throw VocabularyValidationStudyPackageV2Error.invalidCriterion
            }
            if record.phase == .preReading, !record.collectedBeforeReveal {
                throw VocabularyValidationStudyPackageV2Error.invalidCriterion
            }
            if record.firstRaterStatus != record.secondRaterStatus,
               record.status != .ambiguous,
               record.adjudicatedStatus == nil {
                throw VocabularyValidationStudyPackageV2Error.invalidCriterion
            }
            if record.phase == .delayedRetest,
               record.retestLinkageID.map(retestIDs.contains) != true {
                throw VocabularyValidationStudyPackageV2Error.invalidRetest
            }
            let key = [record.assessmentID, record.lexicalItemID.canonicalKey, record.phase.rawValue].joined(separator: "|")
            guard criterionKeys.insert(key).inserted else { throw VocabularyValidationStudyPackageV2Error.duplicateIdentifier }
        }
        var questionKeys = Set<String>()
        for trace in questionTraces {
            guard assessmentByID[trace.assessmentID] != nil,
                  trace.questionOrdinal > 0,
                  trace.predictedKnownBeforeAnswer.isFinite,
                  (0...1).contains(trace.predictedKnownBeforeAnswer),
                  trace.elapsedMilliseconds.isFinite,
                  trace.elapsedMilliseconds >= 0,
                  trace.revealedAfterResponse else {
                throw VocabularyValidationStudyPackageV2Error.invalidQuestionTrace
            }
            guard questionKeys.insert("\(trace.assessmentID)|\(trace.questionOrdinal)").inserted else {
                throw VocabularyValidationStudyPackageV2Error.duplicateIdentifier
            }
        }
        for deck in deckSnapshots {
            guard let assessment = assessmentByID[deck.assessmentID],
                  let document = documentByID[assessment.opaqueStudyDocumentID],
                  deck.inventorySnapshotID == document.inventorySnapshotID else {
                throw VocabularyValidationStudyPackageV2Error.invalidDeck
            }
            try Self.probabilities([deck.targetCoverage, deck.expectedCoverage, deck.conservativeCoverage])
            let available = Set(itemPredictions.filter { $0.assessmentID == deck.assessmentID }.map { $0.lexicalItemID.canonicalKey })
            guard deck.selectedLexicalItemIDs.allSatisfy({ available.contains($0.canonicalKey) }) else {
                throw VocabularyValidationStudyPackageV2Error.invalidDeck
            }
        }
        for manifest in samplingManifests {
            guard documentByID[manifest.opaqueStudyDocumentID] != nil,
                  !manifest.frameHash.trimmedV2.isEmpty,
                  !manifest.designVersion.trimmedV2.isEmpty,
                  manifest.minimumInclusionProbability > 0,
                  manifest.minimumInclusionProbability <= 1,
                  manifest.maximumDesignWeight >= 1,
                  manifest.weightBasedEffectiveSampleSize > 0,
                  manifest.expectedSelectedCardSupport >= 0,
                  manifest.expectedFinalTailSupport >= 0 else {
                throw VocabularyValidationStudyPackageV2Error.invalidSamplingDesign
            }
        }
        for retest in retestManifests {
            guard assessmentByID[retest.assessmentID] != nil,
                  retest.elapsedHours.isFinite,
                  retest.elapsedHours >= 0,
                  !retest.windowVersion.trimmedV2.isEmpty,
                  !retest.missingnessStatus.trimmedV2.isEmpty else {
                throw VocabularyValidationStudyPackageV2Error.invalidRetest
            }
        }
    }

    private static func unique(_ values: [String]) throws {
        try nonempty(values)
        guard Set(values).count == values.count else { throw VocabularyValidationStudyPackageV2Error.duplicateIdentifier }
    }

    private static func nonempty(_ values: [String]) throws {
        guard values.allSatisfy({ !$0.trimmedV2.isEmpty }) else { throw VocabularyValidationStudyPackageV2Error.emptyIdentifier }
    }

    private static func probabilities(_ values: [Double]) throws {
        guard values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw VocabularyValidationStudyPackageV2Error.invalidProbability
        }
    }
}

private extension String {
    var trimmedV2: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
