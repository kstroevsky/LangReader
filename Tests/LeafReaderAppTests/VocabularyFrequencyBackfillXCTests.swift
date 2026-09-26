import Foundation
import XCTest
import LeafReaderCore
@testable import LeafReaderApp

final class VocabularyFrequencyBackfillXCTests: XCTestCase {
    func testPlanRederivesUnverifiedFrequencyAndSkipsCompatibleDerivedValue() throws {
        let provenance = try XCTUnwrap(VocabularyDictionaryMetadataService.frequencyProvenance(
            language: .english,
            languageProfileVersion: "en-profile-v1"
        ))
        let unverified = pdfRecord(
            id: "legacy",
            word: "develop",
            frequency: 99,
            provenance: nil
        )
        let compatible = pdfRecord(
            id: "verified",
            word: "reader",
            frequency: 42,
            provenance: provenance
        )
        let differentLanguage = StoredPDFWordRecord(
            id: "german",
            word: "Haus",
            language: .german,
            pageIndex: 0,
            bounds: StoredPDFWordRect(.zero),
            question: "",
            answer: "house",
            dictionaryFrequency: 12,
            createdAt: Date(timeIntervalSince1970: 1)
        )

        let plan = VocabularyDictionaryMetadataService.pdfFrequencyBackfillPlan(
            [unverified, compatible, differentLanguage],
            provenance: provenance
        )

        XCTAssertEqual(plan.items.map(\.id), ["legacy"])
        XCTAssertEqual(Set(plan.scope.eligibleRecordIDs), ["legacy", "verified"])
        XCTAssertFalse(plan.scope.eligibleRecordIDs.contains("german"))
    }

    func testCompletionInvalidatesForProviderVersionAndRecordCoverageChanges() throws {
        let suite = "VocabularyFrequencyBackfillXCTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = VocabularyReviewPreferences(fileID: "document", defaults: defaults)
        let provenance = try XCTUnwrap(VocabularyDictionaryMetadataService.frequencyProvenance(
            language: .english,
            languageProfileVersion: "en-profile-v1"
        ))
        let record = VocabularyFrequencyBackfillRecordIdentity(
            id: "a",
            lookupText: "develop",
            language: .english,
            lexicalKey: "en|develop|verb|"
        )
        let scope = VocabularyFrequencyBackfillScope(provenance: provenance, eligibleRecords: [record])

        // The pre-ADR boolean must not suppress a versioned backfill.
        defaults.set(true, forKey: "bookSession.document.vocabularyFrequencyBackfilled")
        XCTAssertFalse(preferences.isFrequencyBackfilled(for: scope))

        let completion = VocabularyFrequencyBackfillCompletion(
            scope: scope,
            terminalNotFoundRecordIDs: ["a"]
        )
        preferences.markFrequencyBackfilled(completion)
        XCTAssertTrue(preferences.isFrequencyBackfilled(for: scope))
        XCTAssertEqual(preferences.frequencyBackfillCompletion, completion)

        let expandedScope = VocabularyFrequencyBackfillScope(
            provenance: provenance,
            eligibleRecords: [
                record,
                VocabularyFrequencyBackfillRecordIdentity(
                    id: "b",
                    lookupText: "reader",
                    language: .english,
                    lexicalKey: nil
                )
            ]
        )
        XCTAssertFalse(preferences.isFrequencyBackfilled(for: expandedScope))

        let nextProvider = VocabularyProviderDescriptor(
            id: provenance.provider.id,
            version: "ecdict-v2",
            supportedLanguageRanges: provenance.provider.supportedLanguageRanges,
            normalizationVersion: provenance.provider.normalizationVersion
        )
        let nextProvenance = VocabularyFrequencyProvenance(
            language: provenance.language,
            languageProfileVersion: provenance.languageProfileVersion,
            provider: nextProvider
        )
        let nextScope = VocabularyFrequencyBackfillScope(
            provenance: nextProvenance,
            eligibleRecords: [record]
        )
        XCTAssertFalse(preferences.isFrequencyBackfilled(for: nextScope))
    }

    func testFrequencyProvenanceRoundTripsAcrossSQLiteReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VocabularyFrequencyProvenance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("words.sqlite")
        let provenance = try XCTUnwrap(VocabularyDictionaryMetadataService.frequencyProvenance(
            language: .english,
            languageProfileVersion: "en-profile-v1"
        ))
        let pdf = pdfRecord(
            id: "pdf",
            word: "develop",
            frequency: 123,
            provenance: provenance
        )
        let web = StoredWebWordRecord(
            id: "web",
            vocabularyID: "web-owner",
            word: "reader",
            language: .english,
            lemma: "reader",
            lexicalKey: "en|reader|noun|",
            partOfSpeech: .noun,
            surfaceForm: "reader",
            context: "A reader reads.",
            occurrenceIndex: 0,
            scrollProgress: 0.5,
            question: "",
            answer: "one who reads",
            dictionaryFrequency: 456,
            dictionaryFrequencyProvenance: provenance,
            createdAt: Date(timeIntervalSince1970: 1),
            srs: nil
        )

        do {
            let store = WordRecordSQLiteStore(databaseURL: databaseURL)
            XCTAssertTrue(store.upsertPDFRecord(documentID: "pdf-doc", record: pdf))
            XCTAssertTrue(store.upsertWebRecord(documentID: "web-doc", record: web))
        }

        do {
            let reopened = WordRecordSQLiteStore(databaseURL: databaseURL)
            let loadedPDF = try XCTUnwrap(reopened.loadPDFRecords(documentID: "pdf-doc").first)
            XCTAssertEqual(loadedPDF.dictionaryFrequency, 123)
            XCTAssertEqual(loadedPDF.dictionaryFrequencyProvenance, provenance)
            let loadedWeb = try XCTUnwrap(reopened.loadWebRecords(documentID: "web-doc").first)
            XCTAssertEqual(loadedWeb.dictionaryFrequency, 456)
            XCTAssertEqual(loadedWeb.dictionaryFrequencyProvenance, provenance)
        }
    }

    func testFrequencyFirstReviewIgnoresUnverifiedLegacyRank() throws {
        let provenance = try XCTUnwrap(VocabularyDictionaryMetadataService.frequencyProvenance(
            language: .english,
            languageProfileVersion: "en-profile-v1"
        ))
        let createdAt = Date(timeIntervalSince1970: 1)
        let legacy = exportRecord(
            id: "legacy",
            word: "legacy",
            frequency: 1,
            provenance: nil,
            createdAt: createdAt
        )
        let verified = exportRecord(
            id: "verified",
            word: "verified",
            frequency: 100,
            provenance: provenance,
            createdAt: createdAt.addingTimeInterval(1)
        )

        let queue = VocabularyReviewQueueBuilder.queue(
            records: [legacy, verified],
            priority: .frequencyFirst
        )

        XCTAssertEqual(queue.map(\.word), ["verified", "legacy"])
        XCTAssertNil(legacy.verifiedDictionaryFrequency)
        XCTAssertEqual(verified.verifiedDictionaryFrequency, 100)
    }

    func testLibraryAggregationPrefersVerifiedFrequencyOverLowerLegacyRank() throws {
        let provenance = try XCTUnwrap(VocabularyDictionaryMetadataService.frequencyProvenance(
            language: .english,
            languageProfileVersion: "en-profile-v1"
        ))
        let url = URL(fileURLWithPath: "/tmp/frequency-source.pdf")
        let records = VocabularyLibraryRecordProvider.records(sources: [
            VocabularyLibrarySource(
                documentURL: url,
                documentTitle: "Source",
                documentKind: .pdf,
                records: [
                    exportRecord(
                        id: "legacy",
                        word: "develop",
                        frequency: 1,
                        provenance: nil,
                        createdAt: Date(timeIntervalSince1970: 1)
                    ),
                    exportRecord(
                        id: "verified",
                        word: "develop",
                        frequency: 100,
                        provenance: provenance,
                        createdAt: Date(timeIntervalSince1970: 2)
                    )
                ]
            )
        ])

        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.dictionaryFrequency, 100)
        XCTAssertEqual(record.dictionaryFrequencyProvenance, provenance)
        XCTAssertTrue(record.isDictionaryFrequencyVerified)
    }

    private func pdfRecord(
        id: String,
        word: String,
        frequency: Int?,
        provenance: VocabularyFrequencyProvenance?
    ) -> StoredPDFWordRecord {
        StoredPDFWordRecord(
            id: id,
            vocabularyID: "owner-\(id)",
            word: word,
            language: .english,
            lemma: word,
            pageIndex: 0,
            bounds: StoredPDFWordRect(CGRect(x: 1, y: 2, width: 3, height: 4)),
            context: "Context for \(word)",
            question: "",
            answer: "definition",
            dictionaryFrequency: frequency,
            dictionaryFrequencyProvenance: provenance,
            createdAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func exportRecord(
        id: String,
        word: String,
        frequency: Int,
        provenance: VocabularyFrequencyProvenance?,
        createdAt: Date
    ) -> VocabularyExportRecord {
        VocabularyExportRecord(
            ids: [id],
            word: word,
            language: .english,
            lemma: word,
            lexicalKey: "en|\(word)|noun|",
            partOfSpeech: .noun,
            answer: "definition",
            dictionaryTags: nil,
            dictionaryFrequency: frequency,
            dictionaryFrequencyProvenance: provenance,
            location: "",
            context: "",
            createdAt: createdAt,
            srs: VocabularySRSState.initial(createdAt: createdAt)
        )
    }
}
