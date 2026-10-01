import CryptoKit
import Foundation
import NaturalLanguage
import PDFKit
import XCTest
@testable import LeafReaderCore

final class VocabularyPreparationFixtureXCTests: XCTestCase {
    private struct PipelineCandidate: Equatable {
        let canonicalKey: String
        let occurrenceCount: Int
        let identityPolicy: VocabularyAssessmentIdentityPolicy
        let difficultySource: VocabularyItemDifficultySource
        let difficultyVersion: String
        let generalFrequencyRank: Int?
    }

    private struct PipelineResult: Equatable {
        let candidates: [PipelineCandidate]
        let excludedCount: Int
        let occurrenceDenominator: Int
        let firstEightQuestionKeys: [String]
    }

    private struct Manifest: Decodable {
        struct Fixture: Decodable {
            let language: String
            let format: String
            let path: String
            let sha256: String
            let byteCount: Int

            enum CodingKeys: String, CodingKey {
                case language, format, path, sha256
                case byteCount = "byte_count"
            }
        }

        struct Language: Decodable {
            struct Inventory: Decodable {
                let tokenCount: Int
                let uniqueTokenCount: Int
                let occurrences: [String: Int]

                enum CodingKeys: String, CodingKey {
                    case tokenCount = "token_count"
                    case uniqueTokenCount = "unique_token_count"
                    case occurrences
                }
            }

            let source: String
            let sourceSHA256: String
            let expectedInventory: Inventory

            enum CodingKeys: String, CodingKey {
                case source
                case sourceSHA256 = "source_sha256"
                case expectedInventory = "expected_inventory"
            }
        }

        let schemaVersion: Int
        let fixtureSet: String
        let languages: [String: Language]
        let fixtures: [Fixture]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case fixtureSet = "fixture_set"
            case languages, fixtures
        }
    }

    func testCommittedFixtureChecksumsAndShapeMatchManifest() throws {
        let (root, manifest) = try loadManifest()
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.fixtureSet, "vocabulary-preparation-cross-format-supplement-v1")
        XCTAssertEqual(manifest.fixtures.count, 6)
        XCTAssertEqual(Set(manifest.languages.keys), ["en", "de"])
        XCTAssertEqual(
            Set(manifest.fixtures.map { "\($0.language)-\($0.format)" }),
            ["en-pdf", "en-epub", "en-docx", "de-pdf", "de-epub", "de-docx"]
        )

        for language in manifest.languages.values {
            let data = try Data(contentsOf: root.appendingPathComponent(language.source))
            XCTAssertEqual(hexSHA256(data), language.sourceSHA256)
            XCTAssertGreaterThan(language.expectedInventory.uniqueTokenCount, 250)
        }
        for fixture in manifest.fixtures {
            let data = try Data(contentsOf: root.appendingPathComponent(fixture.path))
            XCTAssertEqual(data.count, fixture.byteCount, fixture.path)
            XCTAssertEqual(hexSHA256(data), fixture.sha256, fixture.path)
        }
    }

    func testPDFEPUBAndDOCXExtractTheCompleteExpectedSurfaceInventory() throws {
        let (root, manifest) = try loadManifest()
        for (languageCode, language) in manifest.languages {
            let expected = language.expectedInventory
            for fixture in manifest.fixtures where fixture.language == languageCode {
                let url = root.appendingPathComponent(fixture.path)
                let actual = inventory(from: try extractedText(from: url, format: fixture.format))
                XCTAssertEqual(actual, expected.occurrences, fixture.path)
                XCTAssertEqual(actual.values.reduce(0, +), expected.tokenCount, fixture.path)
                XCTAssertEqual(actual.count, expected.uniqueTokenCount, fixture.path)
            }
        }
    }

    func testPDFEPUBAndDOCXProduceEquivalentFinalVocabularyPipelinesOnThisHost() throws {
        let (root, manifest) = try loadManifest()
        let host = ProcessInfo.processInfo.operatingSystemVersionString
        for languageCode in manifest.languages.keys.sorted() {
            var results: [(format: String, result: PipelineResult)] = []
            for fixture in manifest.fixtures where fixture.language == languageCode {
                let url = root.appendingPathComponent(fixture.path)
                results.append((fixture.format, try pipelineResult(
                    texts: extractedTextUnits(from: url, format: fixture.format),
                    languageCode: languageCode
                )))
            }
            let baseline = try XCTUnwrap(results.first)
            for result in results.dropFirst() {
                assertEquivalent(
                    baseline.result,
                    result.result,
                    context: "\(languageCode) \(baseline.format) vs \(result.format) on \(host)"
                )
            }
            XCTAssertGreaterThan(baseline.result.candidates.count, 100, languageCode)
            XCTAssertGreaterThan(baseline.result.occurrenceDenominator, 200, languageCode)
            XCTAssertEqual(baseline.result.firstEightQuestionKeys.count, 8, languageCode)
        }
    }

    func testPDFEPUBAndDOCXProduceEquivalentReconciledLexicalPipelinesOnThisHost() throws {
        let (root, manifest) = try loadManifest()
        let host = ProcessInfo.processInfo.operatingSystemVersionString
        for languageCode in manifest.languages.keys.sorted() {
            var results: [(format: String, result: PipelineResult)] = []
            for fixture in manifest.fixtures where fixture.language == languageCode {
                let url = root.appendingPathComponent(fixture.path)
                results.append((fixture.format, try pipelineResult(
                    texts: extractedTextUnits(from: url, format: fixture.format),
                    languageCode: languageCode,
                    useReconciledLexicalIdentity: true
                )))
            }
            let baseline = try XCTUnwrap(results.first)
            for result in results.dropFirst() {
                assertEquivalent(
                    baseline.result,
                    result.result,
                    context: "reconciled \(languageCode) \(baseline.format) vs \(result.format) on \(host)"
                )
            }
            let inferenceCount = baseline.result.candidates.lazy
                .filter { $0.identityPolicy == .fullInference }
                .count
            XCTAssertEqual(
                baseline.result.firstEightQuestionKeys.count,
                min(8, inferenceCount),
                "\(languageCode): live-platform question count should follow resolved inference coverage"
            )
        }
    }

    func testPDFEPUBAndDOCXProduceEquivalentReconciledLexicalPipelinesWithDeterministicEvidence() throws {
        let (root, manifest) = try loadManifest()
        for languageCode in manifest.languages.keys.sorted() {
            var results: [(format: String, result: PipelineResult)] = []
            for fixture in manifest.fixtures where fixture.language == languageCode {
                let url = root.appendingPathComponent(fixture.path)
                results.append((fixture.format, try pipelineResult(
                    texts: extractedTextUnits(from: url, format: fixture.format),
                    languageCode: languageCode,
                    useReconciledLexicalIdentity: true,
                    useDeterministicReconciliationEvidence: true
                )))
            }
            let baseline = try XCTUnwrap(results.first)
            for result in results.dropFirst() {
                assertEquivalent(
                    baseline.result,
                    result.result,
                    context: "deterministic reconciled \(languageCode) \(baseline.format) vs \(result.format)"
                )
            }
            XCTAssertTrue(
                baseline.result.candidates.contains { $0.identityPolicy == .fullInference },
                "\(languageCode): controlled evidence should exercise resolved lexical candidates"
            )
            XCTAssertTrue(
                baseline.result.candidates.contains { $0.identityPolicy == .directEvidenceOnly },
                "\(languageCode): controlled evidence should exercise explicit lexical uncertainty"
            )
        }
    }

    private func loadManifest() throws -> (URL, Manifest) {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/VocabularyPreparation", isDirectory: true)
        let data = try Data(contentsOf: root.appendingPathComponent("manifest.json"))
        return (root, try JSONDecoder().decode(Manifest.self, from: data))
    }

    private func extractedText(from url: URL, format: String) throws -> String {
        try extractedTextUnits(from: url, format: format).joined(separator: "\n\n")
    }

    private func extractedTextUnits(from url: URL, format: String) throws -> [String] {
        switch format {
        case "pdf":
            let document = try XCTUnwrap(PDFDocument(url: url))
            return (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
        case "epub", "docx":
            let document = try WebDocumentLoader.load(url: url)
            return [document.plainText.isEmpty ? (document.plainTextLoader?() ?? "") : document.plainText]
        default:
            XCTFail("Unexpected fixture format: \(format)")
            return []
        }
    }

    private func pipelineResult(
        texts: [String],
        languageCode: String,
        useReconciledLexicalIdentity: Bool = false,
        useDeterministicReconciliationEvidence: Bool = false
    ) throws -> PipelineResult {
        let language: NLLanguage = languageCode == "de" ? .german : .english
        let index: VocabularyDocumentLemmaIndex
        if useDeterministicReconciliationEvidence {
            let resolvedSurface = languageCode == "de" ? "band" : "record"
            index = try XCTUnwrap(VocabularyDocumentLemmaIndex(
                texts: texts,
                language: language,
                maximumWorkerCount: 1,
                resolutionProvider: { surface, _, _ in
                    .resolved(lemma: surface.lowercased(), source: .naturalLanguage)
                },
                analysisProvider: { request in
                    guard request.surface.lowercased() == resolvedSurface else { return [] }
                    return [VocabularyMorphologicalAnalysis(
                        lemma: resolvedSurface,
                        partOfSpeech: .noun,
                        source: .validationFixture,
                        rawScore: 1,
                        confidence: .usable
                    )]
                }
            ))
        } else {
            index = try XCTUnwrap(VocabularyDocumentLemmaIndex(
                texts: texts,
                language: language,
                maximumWorkerCount: 1
            ))
        }
        let summaries = useReconciledLexicalIdentity
            ? index.lexicalSummaries()
            : index.lemmaSummaries()
        let inventory = DocumentVocabularyInventory(
            summaries: summaries,
            languageCode: languageCode,
            difficultyProvider: DocumentVocabularyFrequencyProvider.calibrated(languageCode: languageCode)
        )
        let candidates = inventory.candidates.map {
            PipelineCandidate(
                canonicalKey: $0.canonicalKey,
                occurrenceCount: $0.occurrenceCount,
                identityPolicy: $0.identityPolicy,
                difficultySource: $0.difficultyPrior.source,
                difficultyVersion: $0.difficultyPrior.version,
                generalFrequencyRank: $0.generalFrequencyRank
            )
        }
        var assessment = AdaptiveVocabularyAssessment(inventory: inventory, mode: .allUnknown)
        var questionKeys: [String] = []
        let inferenceCount = candidates.lazy.filter { $0.identityPolicy == .fullInference }.count
        for ordinal in 0..<min(8, inferenceCount) {
            let question = try XCTUnwrap(assessment.nextQuestion())
            questionKeys.append(question.canonicalKey)
            assessment.record(ordinal.isMultiple(of: 3) ? .reportedUnknown : .verifiedKnown, for: question.canonicalKey)
        }
        if inferenceCount == 0 {
            XCTAssertNil(assessment.nextQuestion())
        }
        return PipelineResult(
            candidates: candidates,
            excludedCount: inventory.excludedCount,
            occurrenceDenominator: candidates.reduce(0) { $0 + $1.occurrenceCount },
            firstEightQuestionKeys: questionKeys
        )
    }

    private func assertEquivalent(
        _ expected: PipelineResult,
        _ actual: PipelineResult,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectedByKey = Dictionary(uniqueKeysWithValues: expected.candidates.map { ($0.canonicalKey, $0) })
        let actualByKey = Dictionary(uniqueKeysWithValues: actual.candidates.map { ($0.canonicalKey, $0) })
        let expectedKeys = Set(expectedByKey.keys)
        let actualKeys = Set(actualByKey.keys)
        let missing = expectedKeys.subtracting(actualKeys).sorted()
        let extra = actualKeys.subtracting(expectedKeys).sorted()
        let changed = expectedKeys.intersection(actualKeys).sorted().filter {
            expectedByKey[$0] != actualByKey[$0]
        }
        XCTAssertTrue(
            missing.isEmpty && extra.isEmpty && changed.isEmpty,
            "\(context): missing=\(Array(missing.prefix(12))) extra=\(Array(extra.prefix(12))) changed=\(Array(changed.prefix(12)))",
            file: file,
            line: line
        )
        XCTAssertEqual(actual.candidates.map(\.canonicalKey), expected.candidates.map(\.canonicalKey), "\(context): candidate ordering", file: file, line: line)
        XCTAssertEqual(actual.excludedCount, expected.excludedCount, "\(context): excluded denominator", file: file, line: line)
        XCTAssertEqual(actual.occurrenceDenominator, expected.occurrenceDenominator, "\(context): occurrence denominator", file: file, line: line)
        XCTAssertEqual(actual.firstEightQuestionKeys, expected.firstEightQuestionKeys, "\(context): first eight cold questions", file: file, line: line)
    }

    private func inventory(from text: String) -> [String: Int] {
        let normalized = text.precomposedStringWithCanonicalMapping.lowercased()
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let pattern = #"[^\W\d_]+(?:['’\-][^\W\d_]+)*"#
        let matches = (try? NSRegularExpression(pattern: pattern).matches(in: normalized, range: range)) ?? []
        return matches.reduce(into: [:]) { counts, match in
            guard let range = Range(match.range, in: normalized) else { return }
            counts[String(normalized[range]), default: 0] += 1
        }
    }

    private func hexSHA256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
