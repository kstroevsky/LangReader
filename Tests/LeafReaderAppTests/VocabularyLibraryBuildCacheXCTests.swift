import Foundation
import XCTest
import LeafReaderCore
@testable import LeafReaderApp

final class VocabularyLibraryBuildCacheXCTests: XCTestCase {
    func testFingerprintChangesWithLanguageIdentityAndProfileSemantics() {
        let base = record(language: .english, lexicalKey: "en|gift|noun|", partOfSpeech: .noun)
        let baseFingerprint = fingerprint(base, language: .english, profileVersion: "en-profile-v1")

        XCTAssertNotEqual(
            baseFingerprint,
            fingerprint(record(language: .german, lexicalKey: "de|gift|noun|", partOfSpeech: .noun), language: .german, profileVersion: "de-profile-v1")
        )
        XCTAssertNotEqual(
            baseFingerprint,
            fingerprint(record(language: .english, lexicalKey: "en|gift|verb|", partOfSpeech: .verb), language: .english, profileVersion: "en-profile-v1")
        )
        XCTAssertNotEqual(
            baseFingerprint,
            fingerprint(base, language: .english, profileVersion: "en-profile-v2")
        )
    }

    private func fingerprint(
        _ record: StoredWebWordRecord,
        language: VocabularyLanguageID?,
        profileVersion: String?
    ) -> Int {
        VocabularyLibraryBuildCache.fingerprint(
            pdf: [],
            web: [record],
            labelGeneration: 1,
            language: language,
            languageProfileVersion: profileVersion
        )
    }

    private func record(
        language: VocabularyLanguageID,
        lexicalKey: String,
        partOfSpeech: VocabularyPartOfSpeech
    ) -> StoredWebWordRecord {
        StoredWebWordRecord(
            id: "record",
            vocabularyID: "owner",
            word: "Gift",
            language: language,
            lemma: "gift",
            lexicalKey: lexicalKey,
            partOfSpeech: partOfSpeech,
            surfaceForm: "Gift",
            context: "context",
            occurrenceIndex: 1,
            scrollProgress: 0.5,
            question: "",
            answer: "definition",
            createdAt: Date(timeIntervalSince1970: 1)
        )
    }
}
