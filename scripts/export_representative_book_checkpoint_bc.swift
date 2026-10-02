import Foundation
import LeafReaderCore
import NaturalLanguage

private struct FinalAssignment {
    let finalLexicalKey: String?
    let resolutionState: String
    let assessmentIdentityPolicy: String
    let reconcilerVersion: String
}

private func assignments(
    occurrences: [VocabularyOccurrenceAnalysis]
) -> [VocabularyOccurrenceAnalysisID: FinalAssignment] {
    let reconciler = VocabularyLexicalReconciler()
    let byAnchor = Dictionary(grouping: occurrences, by: \.anchor)
    var result: [VocabularyOccurrenceAnalysisID: FinalAssignment] = [:]

    func set(
        ids: [VocabularyOccurrenceAnalysisID],
        finalKey: String?,
        state: VocabularyLexicalResolutionState,
        policy: String,
        reconcilerVersion: String
    ) {
        for id in ids {
            result[id] = FinalAssignment(
                finalLexicalKey: finalKey,
                resolutionState: state.rawValue,
                assessmentIdentityPolicy: policy,
                reconcilerVersion: reconcilerVersion
            )
        }
    }

    for anchor in byAnchor.keys.sorted(by: { $0.canonicalKey < $1.canonicalKey }) {
        let resolution = reconciler.reconcile(anchor: anchor, occurrences: byAnchor[anchor] ?? [])
        switch resolution {
        case .resolvedSingle(let group):
            set(
                ids: group.assignedOccurrenceIDs,
                finalKey: group.lexicalItemID.canonicalKey,
                state: .resolvedSingle,
                policy: "fullInference",
                reconcilerVersion: group.diagnostics.reconcilerVersion
            )
            set(
                ids: group.residualOccurrenceIDs,
                finalKey: nil,
                state: .resolvedSingle,
                policy: "directEvidenceOnly",
                reconcilerVersion: group.diagnostics.reconcilerVersion
            )
        case .resolvedSplit(let partition):
            for child in partition.children {
                set(
                    ids: child.assignedOccurrenceIDs,
                    finalKey: child.lexicalItemID.canonicalKey,
                    state: .resolvedSplit,
                    policy: "fullInference",
                    reconcilerVersion: partition.diagnostics.reconcilerVersion
                )
            }
            set(
                ids: partition.residualOccurrenceIDs,
                finalKey: nil,
                state: .resolvedSplit,
                policy: "directEvidenceOnly",
                reconcilerVersion: partition.diagnostics.reconcilerVersion
            )
        case .ambiguous(let group):
            set(
                ids: group.occurrenceIDs,
                finalKey: nil,
                state: .ambiguous,
                policy: "directEvidenceOnly",
                reconcilerVersion: group.diagnostics.reconcilerVersion
            )
        case .unresolved(let group):
            set(
                ids: group.occurrenceIDs,
                finalKey: nil,
                state: .unresolved,
                policy: "directEvidenceOnly",
                reconcilerVersion: group.diagnostics.reconcilerVersion
            )
        }
    }
    return result
}

private func strongestPart(_ analyses: [VocabularyMorphologicalAnalysis]) -> String? {
    analyses.first(where: { $0.confidence == .strong || $0.confidence == .usable })?.partOfSpeech.rawValue
        ?? analyses.first?.partOfSpeech.rawValue
}

private func exportCheckpoint(
    bundle: RepresentativeBookSampleBundle,
    checkpointID: String,
    revision: String,
    harnessSHA256: String
) throws -> RepresentativeBookCheckpointExport {
    let detectedLanguage: String?
    let routedLanguage: String?
    let index: VocabularyDocumentLemmaIndex
    let runtimeDescription: String
    let languageSelectionMode: String

    #if CHECKPOINT_C
    guard let requestedLanguage = VocabularyLanguageID(bundle.languageCode) else {
        throw RepresentativeBookCheckpointExportError.invalid("invalid BCP-47 language in sample bundle")
    }
    let detection = VocabularyLanguageDetector.resolution(
        pageCount: bundle.sampledTexts.count,
        pageText: { bundle.sampledTexts.indices.contains($0) ? bundle.sampledTexts[$0] : nil },
        recognizer: AppleVocabularyLanguageRecognizer()
    )
    let resolvedLanguage: VocabularyLanguageID?
    switch detection {
    case .resolved(let resolved):
        resolvedLanguage = resolved.id
    case .undetermined:
        resolvedLanguage = nil
    }
    detectedLanguage = resolvedLanguage?.bcp47
    routedLanguage = resolvedLanguage?.bcp47
    let indexLanguage = resolvedLanguage ?? requestedLanguage
    let capabilities = resolvedLanguage.map(AppleVocabularyLinguisticCapabilities.probe)
        ?? AppleVocabularyLinguisticCapabilities(availableTagSchemes: [])
    guard let built = VocabularyDocumentLemmaIndex(
        texts: bundle.sampledTexts,
        language: indexLanguage,
        maximumWorkerCount: 1,
        analyzerFactory: capabilities.analyzerFactory
    ) else {
        throw RepresentativeBookCheckpointExportError.invalid("checkpoint C could not build vocabulary index")
    }
    index = built
    runtimeDescription = capabilities.runtimeSignature
    languageSelectionMode = resolvedLanguage == nil
        ? "automaticDetectionUndetermined;requestedLanguageExactFormDegradation"
        : "automaticDetection"
    #else
    detectedLanguage = nil
    routedLanguage = bundle.languageCode
    guard let built = VocabularyDocumentLemmaIndex(
        texts: bundle.sampledTexts,
        language: NLLanguage(rawValue: bundle.languageCode),
        maximumWorkerCount: 1
    ) else {
        throw RepresentativeBookCheckpointExportError.invalid("checkpoint B could not build vocabulary index")
    }
    index = built
    runtimeDescription = "Apple NaturalLanguage; pre-ADR-0002 routing"
    languageSelectionMode = "requestedLanguage"
    #endif

    let occurrences = index.lexicalOccurrenceAnalyses()
    let finalByID = assignments(occurrences: occurrences)
    let records = occurrences.compactMap { occurrence -> RepresentativeBookCheckpointRecord? in
        let range = occurrence.sourceRange
        guard bundle.sampledTexts.indices.contains(range.unitIndex),
              bundle.sampledUnitNumbers.indices.contains(range.unitIndex) else { return nil }
        let final = finalByID[occurrence.occurrenceID]
        let physicalID = representativeBookPhysicalOccurrenceID(
            unitIndex: range.unitIndex,
            location: range.utf16Location,
            length: range.utf16Length
        )
        let analysisRows = occurrence.analyses.map {
            RepresentativeBookExportAnalysis(
                lemma: $0.lemma,
                partOfSpeech: $0.partOfSpeech.rawValue,
                source: $0.source.rawValue,
                rawScore: $0.rawScore,
                confidence: $0.confidence.rawValue
            )
        }
        let providerNames = Array(Set(occurrence.analyses.map(\.source.rawValue))).sorted()
        return RepresentativeBookCheckpointRecord(
            assignmentID: representativeBookSHA256(
                "\(physicalID)|\(final?.finalLexicalKey ?? occurrence.anchor.canonicalKey)"
            ),
            physicalOccurrenceID: physicalID,
            sampledUnitIndex: range.unitIndex,
            sourceUnitNumber: bundle.sampledUnitNumbers[range.unitIndex],
            utf16Location: range.utf16Location,
            utf16Length: range.utf16Length,
            surface: occurrence.surface,
            requestedLanguage: bundle.languageCode,
            detectedLanguage: detectedLanguage,
            routedLanguage: routedLanguage,
            lemmaOrAnchor: occurrence.anchor.displayValue,
            anchorKey: occurrence.anchor.canonicalKey,
            predictedPartOfSpeech: strongestPart(occurrence.analyses),
            finalLexicalKey: final?.finalLexicalKey,
            resolutionState: final?.resolutionState,
            assessmentIdentityPolicy: final?.assessmentIdentityPolicy,
            contextFingerprint: occurrence.contextFingerprint,
            providers: providerNames,
            reconcilerVersion: final?.reconcilerVersion,
            analyses: analysisRows
        )
    }.sorted {
        if $0.sampledUnitIndex != $1.sampledUnitIndex {
            return $0.sampledUnitIndex < $1.sampledUnitIndex
        }
        if $0.utf16Location != $1.utf16Location { return $0.utf16Location < $1.utf16Location }
        if $0.utf16Length != $1.utf16Length { return $0.utf16Length < $1.utf16Length }
        return $0.assignmentID < $1.assignmentID
    }

    return RepresentativeBookCheckpointExport(
        schemaVersion: 1,
        checkpoint: RepresentativeBookCheckpointDescriptor(id: checkpointID, revision: revision),
        documentAlias: bundle.documentAlias,
        sourceSHA256: bundle.sourceSHA256,
        annotationSHA256: bundle.annotationSHA256,
        candidateSelectionPolicyVersion: bundle.candidateSelectionPolicyVersion,
        sampledTextSHA256: bundle.sampledTextSHA256,
        languageCode: bundle.languageCode,
        documentFormat: bundle.documentFormat,
        dataRole: bundle.dataRole,
        sourceUnitKind: bundle.sourceUnitKind,
        sourceUnitCount: bundle.sourceUnitCount,
        sampledUnitNumbers: bundle.sampledUnitNumbers,
        environment: representativeBookEnvironment(
            naturalLanguageRuntime: runtimeDescription,
            languageSelectionMode: languageSelectionMode,
            experimentHarnessSHA256: harnessSHA256
        ),
        records: records
    )
}

@main
private enum CheckpointBCExporterCLI {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard arguments.count == 5 else {
                throw RepresentativeBookCheckpointExportError.usage
            }
            let bundle = try representativeBookReadBundle(arguments[0])
            let result = try exportCheckpoint(
                bundle: bundle,
                checkpointID: arguments[2],
                revision: arguments[3],
                harnessSHA256: arguments[4]
            )
            try representativeBookWriteExport(result, path: arguments[1])
            print("wrote \(result.records.count) checkpoint-\(arguments[2]) occurrence records")
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(2)
        }
    }
}
