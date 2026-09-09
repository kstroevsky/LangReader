import CryptoKit
import Foundation
import PDFKit
import XCTest
@testable import LeafReaderCore

final class VocabularyPreparationFixtureXCTests: XCTestCase {
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

    private func loadManifest() throws -> (URL, Manifest) {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/VocabularyPreparation", isDirectory: true)
        let data = try Data(contentsOf: root.appendingPathComponent("manifest.json"))
        return (root, try JSONDecoder().decode(Manifest.self, from: data))
    }

    private func extractedText(from url: URL, format: String) throws -> String {
        switch format {
        case "pdf":
            return try XCTUnwrap(PDFDocument(url: url)?.string)
        case "epub", "docx":
            let document = try WebDocumentLoader.load(url: url)
            return document.plainText.isEmpty ? (document.plainTextLoader?() ?? "") : document.plainText
        default:
            XCTFail("Unexpected fixture format: \(format)")
            return ""
        }
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
