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

    func testFingerprintChangesWithLinguisticRuntimeSemantics() {
        let base = record(language: .english, lexicalKey: "en|gift|noun|", partOfSpeech: .noun)
        let current = VocabularyLinguisticCacheIdentity(
            language: .english,
            languageProfileVersion: "en-profile-v1",
            linguisticRuntimeSignature: "runtime-a"
        )
        let changed = VocabularyLinguisticCacheIdentity(
            language: .english,
            languageProfileVersion: "en-profile-v1",
            linguisticRuntimeSignature: "runtime-b"
        )

        XCTAssertNotEqual(fingerprint(base, semanticIdentity: current), fingerprint(base, semanticIdentity: changed))
    }

    private func fingerprint(
        _ record: StoredWebWordRecord,
        language: VocabularyLanguageID?,
        profileVersion: String?
    ) -> Int {
        fingerprint(
            record,
            semanticIdentity: language.map {
                VocabularyLinguisticCacheIdentity(language: $0, languageProfileVersion: profileVersion)
            }
        )
    }

    private func fingerprint(
        _ record: StoredWebWordRecord,
        semanticIdentity: VocabularyLinguisticCacheIdentity?
    ) -> Int {
        VocabularyLibraryBuildCache.fingerprint(
            pdf: [],
            web: [record],
            labelGeneration: 1,
            semanticIdentity: semanticIdentity
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
