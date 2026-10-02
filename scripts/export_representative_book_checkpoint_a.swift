import Foundation
import LeafReaderCore
import NaturalLanguage

private func exportBaseline(
    bundle: RepresentativeBookSampleBundle,
    checkpointID: String,
    revision: String,
    harnessSHA256: String
) throws -> RepresentativeBookCheckpointExport {
    guard let index = VocabularyDocumentLemmaIndex(
        texts: bundle.sampledTexts,
        language: NLLanguage(rawValue: bundle.languageCode),
        maximumWorkerCount: 1
    ) else {
        throw RepresentativeBookCheckpointExportError.invalid("checkpoint A could not build vocabulary index")
    }

    var records: [RepresentativeBookCheckpointRecord] = []
    for summary in index.lemmaSummaries() {
        let matches = index.matches(
            lemma: summary.displayLemma,
            selectedForm: summary.displayLemma
        )
        for (unitIndex, occurrences) in matches.enumerated() {
            guard bundle.sampledUnitNumbers.indices.contains(unitIndex) else { continue }
            for occurrence in occurrences {
                let physicalID = representativeBookPhysicalOccurrenceID(
                    unitIndex: unitIndex,
                    location: occurrence.range.location,
                    length: occurrence.range.length
                )
                records.append(RepresentativeBookCheckpointRecord(
                    assignmentID: representativeBookSHA256(
                        "\(physicalID)|\(summary.canonicalKey)"
                    ),
                    physicalOccurrenceID: physicalID,
                    sampledUnitIndex: unitIndex,
                    sourceUnitNumber: bundle.sampledUnitNumbers[unitIndex],
                    utf16Location: occurrence.range.location,
                    utf16Length: occurrence.range.length,
                    surface: occurrence.matchedText,
                    requestedLanguage: bundle.languageCode,
                    detectedLanguage: nil,
                    routedLanguage: bundle.languageCode,
                    lemmaOrAnchor: summary.lemmaKey,
                    anchorKey: nil,
                    predictedPartOfSpeech: summary.partOfSpeech.rawValue,
                    finalLexicalKey: summary.canonicalKey,
                    resolutionState: nil,
                    assessmentIdentityPolicy: nil,
                    contextFingerprint: representativeBookContextFingerprint(
                        text: bundle.sampledTexts[unitIndex],
                        location: occurrence.range.location,
                        length: occurrence.range.length
                    ),
                    providers: ["appleNaturalLanguage@osManaged"],
                    reconcilerVersion: nil,
                    analyses: []
                ))
            }
        }
    }
    records.sort {
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
            naturalLanguageRuntime: "Apple NaturalLanguage; model revision not exposed",
            languageSelectionMode: "requestedLanguage",
            experimentHarnessSHA256: harnessSHA256
        ),
        records: records
    )
}

@main
private enum CheckpointABaselineExporterCLI {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard arguments.count == 5 else {
                throw RepresentativeBookCheckpointExportError.usage
            }
            let bundle = try representativeBookReadBundle(arguments[0])
            let result = try exportBaseline(
                bundle: bundle,
                checkpointID: arguments[2],
                revision: arguments[3],
                harnessSHA256: arguments[4]
            )
            try representativeBookWriteExport(result, path: arguments[1])
            print("wrote \(result.records.count) checkpoint-A assignments")
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(2)
        }
    }
}
