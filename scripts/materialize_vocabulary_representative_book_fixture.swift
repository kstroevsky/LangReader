import CryptoKit
import Foundation
import LeafReaderCore
import NaturalLanguage
import PDFKit

private struct AnnotationTemplate: Decodable {
    struct Source: Decodable {
        let alias: String
        let fileName: String
        let sourceSHA256: String
        let languageCode: String
        let genre: String
        let documentFormat: String
        let dataRole: String
        let pageCount: Int
        let sampledPageNumbers: [Int]
    }

    struct Anchor: Decodable {
        let anchorID: String
        let occurrences: [Occurrence]
    }

    struct Occurrence: Decodable {
        let occurrenceID: String
        let pageNumber: Int
        let sampledUnitIndex: Int
        let utf16Location: Int
        let utf16Length: Int
        let surface: String
        let goldLemma: String
        let goldPartOfSpeech: String
        let reviewStatus: String
    }

    let schemaVersion: Int
    let candidateSelectionPolicyVersion: String
    let sampledTextSHA256: String
    let source: Source
    let anchors: [Anchor]
}

private struct Fixture: Encodable {
    struct AnchorBasis: Encodable {
        let kind: String
        let value: String
    }

    struct Analysis: Encodable {
        let lemma: String
        let partOfSpeech: String
        let source: String
        let rawScore: Double?
        let confidence: String
    }

    struct Occurrence: Encodable {
        let occurrenceID: String
        let surface: String
        let goldLemma: String
        let goldPartOfSpeech: String
        let contextFingerprint: String
        let analyses: [Analysis]
    }

    struct Anchor: Encodable {
        let anchorID: String
        let languageCode: String
        let evaluationSplit: String
        let genre: String
        let documentFormat: String
        let nlpAvailability: String
        let dictionaryAttestationAvailability: String
        let anchor: AnchorBasis
        let attributes: [String: String]
        let occurrences: [Occurrence]
    }

    let schemaVersion: Int
    let fixtureID: String
    let release: String
    let supportThresholds: [Int]
    let anchors: [Anchor]
}

private struct ReviewedOccurrence {
    let annotation: AnnotationTemplate.Occurrence
    let analysis: VocabularyOccurrenceAnalysis
    let goldPartOfSpeech: VocabularyPartOfSpeech
}

private enum MaterializeError: Error, CustomStringConvertible {
    case usage
    case invalid(String)

    var description: String {
        switch self {
        case .usage:
            return "usage: materialize_vocabulary_representative_book_fixture.swift <annotation.json> <source.pdf> <fixture.json> | --self-test"
        case .invalid(let message):
            return message
        }
    }
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func occurrenceKey(unitIndex: Int, location: Int, length: Int) -> String {
    "\(unitIndex):\(location):\(length)"
}

private func normalizedGoldLemma(_ value: String) -> String {
    VocabularyTextPolicy.canonicalVocabularyKey(value)
}

private func fixtureAnchors(
    template: AnnotationTemplate,
    observations: [VocabularyOccurrenceAnalysis]
) throws -> [Fixture.Anchor] {
    let byRange = Dictionary(grouping: observations) {
        occurrenceKey(
            unitIndex: $0.sourceRange.unitIndex,
            location: $0.sourceRange.utf16Location,
            length: $0.sourceRange.utf16Length
        )
    }

    let reviewed = try template.anchors.flatMap(\.occurrences).compactMap { occurrence -> ReviewedOccurrence? in
        guard occurrence.reviewStatus == "approved" else { return nil }
        let goldLemma = normalizedGoldLemma(occurrence.goldLemma)
        guard !goldLemma.isEmpty else {
            throw MaterializeError.invalid("approved occurrence \(occurrence.occurrenceID) has no gold lemma")
        }
        guard let goldPOS = VocabularyPartOfSpeech(rawValue: occurrence.goldPartOfSpeech),
              goldPOS != .unknown else {
            throw MaterializeError.invalid("approved occurrence \(occurrence.occurrenceID) has invalid gold POS")
        }
        let key = occurrenceKey(
            unitIndex: occurrence.sampledUnitIndex,
            location: occurrence.utf16Location,
            length: occurrence.utf16Length
        )
        guard let matches = byRange[key], matches.count == 1, let analysis = matches.first else {
            throw MaterializeError.invalid(
                "approved occurrence \(occurrence.occurrenceID) does not match exactly one Core observation"
            )
        }
        guard analysis.surface == occurrence.surface else {
            throw MaterializeError.invalid(
                "approved occurrence \(occurrence.occurrenceID) surface changed: annotation=\(occurrence.surface) core=\(analysis.surface)"
            )
        }
        return ReviewedOccurrence(annotation: occurrence, analysis: analysis, goldPartOfSpeech: goldPOS)
    }
    guard !reviewed.isEmpty else {
        throw MaterializeError.invalid("annotation contains no approved occurrences")
    }

    let byGoldLemma = Dictionary(grouping: reviewed) {
        normalizedGoldLemma($0.annotation.goldLemma)
    }
    return byGoldLemma.keys.sorted().map { goldLemma in
        let rows = (byGoldLemma[goldLemma] ?? []).sorted {
            if $0.analysis.sourceRange.unitIndex != $1.analysis.sourceRange.unitIndex {
                return $0.analysis.sourceRange.unitIndex < $1.analysis.sourceRange.unitIndex
            }
            return $0.analysis.sourceRange.utf16Location < $1.analysis.sourceRange.utf16Location
        }
        let mismatchCount = rows.filter {
            $0.analysis.anchor.resolvedLemma != goldLemma
        }.count
        let occurrenceRows = rows.map { row in
            Fixture.Occurrence(
                occurrenceID: row.annotation.occurrenceID,
                surface: row.analysis.surface,
                goldLemma: goldLemma,
                goldPartOfSpeech: row.goldPartOfSpeech.rawValue,
                contextFingerprint: row.analysis.contextFingerprint,
                analyses: row.analysis.analyses.map {
                    Fixture.Analysis(
                        lemma: $0.lemma,
                        partOfSpeech: $0.partOfSpeech.rawValue,
                        source: $0.source.rawValue,
                        rawScore: $0.rawScore,
                        confidence: $0.confidence.rawValue
                    )
                }
            )
        }
        let anchorDigest = String(sha256(Data(goldLemma.utf8)).prefix(12))
        return Fixture.Anchor(
            anchorID: "\(template.source.alias)-\(anchorDigest)",
            languageCode: template.source.languageCode,
            evaluationSplit: "development",
            genre: template.source.genre,
            documentFormat: template.source.documentFormat,
            nlpAvailability: "available",
            dictionaryAttestationAvailability: "unavailable",
            anchor: Fixture.AnchorBasis(kind: "resolvedLemma", value: goldLemma),
            attributes: [
                "sourceAlias": template.source.alias,
                "reviewedOccurrenceCount": String(rows.count),
                "observedAnchorMismatchCount": String(mismatchCount),
                "scope": "reconciliation-conditional-on-reviewed-gold-anchor"
            ],
            occurrences: occurrenceRows
        )
    }
}

private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(value)
    data.append(0x0A)
    try data.write(to: url, options: .atomic)
}

private func materialize(annotationURL: URL, sourceURL: URL, outputURL: URL) throws {
    let template = try JSONDecoder().decode(
        AnnotationTemplate.self,
        from: Data(contentsOf: annotationURL)
    )
    guard template.schemaVersion == 1,
          template.source.dataRole == "development",
          template.source.documentFormat == "pdf" else {
        throw MaterializeError.invalid("only schema-v1 development PDF annotations are accepted")
    }
    let sourceData = try Data(contentsOf: sourceURL)
    guard sha256(sourceData) == template.source.sourceSHA256 else {
        throw MaterializeError.invalid("source PDF SHA-256 does not match annotation provenance")
    }
    guard let document = PDFDocument(url: sourceURL), document.pageCount == template.source.pageCount else {
        throw MaterializeError.invalid("source PDF page count does not match annotation provenance")
    }
    let texts = try template.source.sampledPageNumbers.map { pageNumber -> String in
        guard pageNumber >= 1, pageNumber <= document.pageCount,
              let text = document.page(at: pageNumber - 1)?.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MaterializeError.invalid("sampled PDF page \(pageNumber) is unavailable or has no text")
        }
        return text
    }
    let sampledText = texts.joined(separator: "\n\u{001E}\n")
    guard sha256(Data(sampledText.utf8)) == template.sampledTextSHA256 else {
        throw MaterializeError.invalid("sampled PDF text changed since annotation generation")
    }

    let language = NLLanguage(rawValue: template.source.languageCode)
    guard let index = VocabularyDocumentLemmaIndex(
        texts: texts,
        language: language,
        maximumWorkerCount: 1
    ) else {
        throw MaterializeError.invalid("Core vocabulary index could not be built")
    }
    let anchors = try fixtureAnchors(
        template: template,
        observations: index.lexicalOccurrenceAnalyses()
    )
    let fixture = Fixture(
        schemaVersion: 1,
        fixtureID: "representative-\(template.source.alias)-development-v1",
        release: "development-representative-prose-v1",
        supportThresholds: [2, 3, 4],
        anchors: anchors
    )
    try writeJSON(fixture, to: outputURL)
    print("wrote \(anchors.count) reviewed lexical anchors to \(outputURL.path)")
}

private func selfTest() throws {
    let source = AnnotationTemplate.Source(
        alias: "self-test",
        fileName: "self-test.pdf",
        sourceSHA256: "unused",
        languageCode: "en",
        genre: "synthetic",
        documentFormat: "pdf",
        dataRole: "development",
        pageCount: 1,
        sampledPageNumbers: [1]
    )
    let occurrences = [
        AnnotationTemplate.Occurrence(
            occurrenceID: "noun-1",
            pageNumber: 1,
            sampledUnitIndex: 0,
            utf16Location: 0,
            utf16Length: 6,
            surface: "record",
            goldLemma: "record",
            goldPartOfSpeech: "noun",
            reviewStatus: "approved"
        ),
        AnnotationTemplate.Occurrence(
            occurrenceID: "verb-1",
            pageNumber: 1,
            sampledUnitIndex: 0,
            utf16Location: 10,
            utf16Length: 6,
            surface: "record",
            goldLemma: "record",
            goldPartOfSpeech: "verb",
            reviewStatus: "approved"
        )
    ]
    let template = AnnotationTemplate(
        schemaVersion: 1,
        candidateSelectionPolicyVersion: "self-test",
        sampledTextSHA256: "unused",
        source: source,
        anchors: [AnnotationTemplate.Anchor(anchorID: "record", occurrences: occurrences)]
    )
    func observation(location: Int, part: VocabularyPartOfSpeech) -> VocabularyOccurrenceAnalysis {
        let range = VocabularyDocumentSourceRange(unitIndex: 0, utf16Location: location, utf16Length: 6)
        return VocabularyOccurrenceAnalysis(
            occurrenceID: VocabularyOccurrenceAnalysisID(
                unitIndex: 0,
                utf16Location: location,
                utf16Length: 6
            ),
            sourceRange: range,
            surface: "record",
            anchor: VocabularyLexicalAnchorID(language: "en", basis: .resolvedLemma("record")),
            analyses: [VocabularyMorphologicalAnalysis(
                lemma: "record",
                partOfSpeech: part,
                source: .validationFixture,
                rawScore: 1,
                confidence: .usable
            )],
            contextFingerprint: "context-\(location)"
        )
    }
    let anchors = try fixtureAnchors(
        template: template,
        observations: [observation(location: 0, part: .noun), observation(location: 10, part: .verb)]
    )
    guard anchors.count == 1,
          anchors[0].occurrences.map(\.goldPartOfSpeech) == ["noun", "verb"],
          anchors[0].occurrences.map(\.analyses).allSatisfy({ $0.count == 1 }) else {
        throw MaterializeError.invalid("representative fixture materializer self-test failed")
    }
    print("representative book fixture materializer self-test passed")
}

@main
private enum RepresentativeBookFixtureMaterializerCLI {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments == ["--self-test"] {
                try selfTest()
            } else {
                guard arguments.count == 3 else { throw MaterializeError.usage }
                try materialize(
                    annotationURL: URL(fileURLWithPath: arguments[0]),
                    sourceURL: URL(fileURLWithPath: arguments[1]),
                    outputURL: URL(fileURLWithPath: arguments[2])
                )
            }
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(2)
        }
    }
}
