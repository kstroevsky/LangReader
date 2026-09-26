import XCTest
@testable import LeafReaderCore

final class VocabularyLanguageXCTests: XCTestCase {
    private struct FixtureRecognizer: VocabularyLanguageRecognizing {
        let descriptor = VocabularyProviderDescriptor(
            id: "language.fixture",
            version: "1",
            supportedLanguageRanges: []
        )
        let observation: VocabularyLanguageRecognitionObservation
        let shouldThrow: Bool

        init(
            dominant: VocabularyLanguageID?,
            candidates: [VocabularyLanguageCandidate] = [],
            shouldThrow: Bool = false
        ) {
            observation = VocabularyLanguageRecognitionObservation(
                dominant: dominant.map { VocabularyLanguageCandidate(language: $0, rawScore: 0.9) },
                candidates: candidates
            )
            self.shouldThrow = shouldThrow
        }

        func recognize(sample: String) throws -> VocabularyLanguageRecognitionObservation {
            if shouldThrow { throw FixtureError.failed }
            return observation
        }
    }

    private enum FixtureError: Error { case failed }

    func testCanonicalizesBCP47WithoutDroppingScriptOrRegion() throws {
        for (raw, expected) in [
            ("EN", "en"),
            ("pt-br", "pt-BR"),
            ("zh-hant", "zh-Hant"),
            ("sr-latn-rs", "sr-Latn-RS")
        ] {
            XCTAssertEqual(try XCTUnwrap(VocabularyLanguageID(raw)).bcp47, expected)
        }
    }

    func testRejectsSpecialAndLocaleStyleTagsFromResolvedIdentity() {
        for raw in ["und", "mul", "zxx", "en_US", "en-US-u-ca-gregory", "x-private"] {
            XCTAssertNil(VocabularyLanguageID(raw))
        }
    }

    func testCodableUsesSingleCanonicalString() throws {
        let value = try XCTUnwrap(VocabularyLanguageID("PT-br"))
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"pt-BR\"")
        XCTAssertEqual(try JSONDecoder().decode(VocabularyLanguageID.self, from: data), value)
    }

    func testProviderMatchingIsFailClosedAndRangeSpecific() throws {
        let de = VocabularyProviderDescriptor(
            id: "dictionary.de",
            version: "1",
            supportedLanguageRanges: [try XCTUnwrap(VocabularyLanguageRange("de-*"))]
        )
        let en = VocabularyProviderDescriptor(
            id: "dictionary.en",
            version: "1",
            supportedLanguageRanges: [try XCTUnwrap(VocabularyLanguageRange("en-*"))]
        )
        let exact = VocabularyProviderDescriptor(
            id: "dictionary.de-at",
            version: "1",
            supportedLanguageRanges: [try XCTUnwrap(VocabularyLanguageRange("de-AT"))]
        )

        XCTAssertEqual(
            VocabularyProviderSelection.select(
                language: try XCTUnwrap(VocabularyLanguageID("de-AT")),
                descriptors: [en, de, exact]
            ),
            .selected(exact)
        )
        XCTAssertEqual(
            VocabularyProviderSelection.select(
                language: try XCTUnwrap(VocabularyLanguageID("de-CH")),
                descriptors: [en, de, exact]
            ),
            .selected(de)
        )
        XCTAssertEqual(
            VocabularyProviderSelection.select(
                language: try XCTUnwrap(VocabularyLanguageID("fr")),
                descriptors: [en, de, exact]
            ),
            .unavailable
        )
    }

    func testAmbiguousEqualSpecificityRegistrationFailsClosed() throws {
        let first = VocabularyProviderDescriptor(
            id: "dictionary.en.a",
            version: "1",
            supportedLanguageRanges: [try XCTUnwrap(VocabularyLanguageRange("en-*"))]
        )
        let second = VocabularyProviderDescriptor(
            id: "dictionary.en.b",
            version: "1",
            supportedLanguageRanges: [try XCTUnwrap(VocabularyLanguageRange("en-*"))]
        )
        let language = try XCTUnwrap(VocabularyLanguageID("en-GB"))

        XCTAssertEqual(
            VocabularyProviderSelection.select(language: language, descriptors: [first, second]),
            .ambiguous([first, second])
        )
        XCTAssertEqual(
            VocabularyProviderSelection.select(
                language: language,
                descriptors: [second, first],
                priorityByProviderID: [second.id: 10]
            ),
            .selected(second)
        )
    }

    func testDetectionAbstainsForShortAndInconclusiveSamples() {
        let short = VocabularyLanguageDetector.resolution(
            forSample: "kort",
            recognizer: FixtureRecognizer(dominant: .english)
        )
        guard case let .undetermined(evidence) = short else {
            return XCTFail("short sample should remain undetermined")
        }
        XCTAssertEqual(evidence.undeterminedReason, .insufficientText)

        let prose = String(repeating: "ordinary prose words for recognition ", count: 20)
        let inconclusive = VocabularyLanguageDetector.resolution(
            forSample: prose,
            recognizer: FixtureRecognizer(dominant: nil)
        )
        guard case let .undetermined(inconclusiveEvidence) = inconclusive else {
            return XCTFail("missing dominant result should remain undetermined")
        }
        XCTAssertEqual(inconclusiveEvidence.undeterminedReason, .inconclusiveRecognition)
    }

    func testDetectionRetainsRecognizedUnsupportedLanguage() {
        let prose = String(repeating: "testo italiano abbastanza lungo per riconoscimento ", count: 20)
        let resolution = VocabularyLanguageDetector.resolution(
            forSample: prose,
            recognizer: FixtureRecognizer(dominant: .italian)
        )
        guard case let .resolved(resolved) = resolution else {
            return XCTFail("recognized Italian should remain resolved")
        }
        XCTAssertEqual(resolved.id, .italian)
        XCTAssertEqual(resolved.provenance, .automaticDetection)
    }

    func testManualResolutionIsDistinctFromAutomaticDetection() {
        let manual: VocabularyLanguageResolution = .resolved(VocabularyResolvedLanguage(
            id: .german,
            provenance: .userSelected
        ))
        XCTAssertEqual(manual.languageID, .german)
        XCTAssertEqual(manual.resolvedLanguage?.provenance, .userSelected)
    }
}
