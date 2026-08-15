import Foundation
import SQLite3
import XCTest
import LeafReaderCore
@testable import LeafReaderApp

final class VocabularyPreparationPersistenceXCTests: XCTestCase {
    func testDocumentScopedSessionRoundTripAndClear() throws {
        let suite = "VocabularyPreparationPersistenceXCTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = VocabularyPreparationSessionStore(documentID: "document-a", defaults: defaults)
        let session = VocabularyPreparationSession(
            mode: .targetCoverage(0.98),
            invitationState: .started,
            answers: [
                VocabularyAssessmentAnswer(canonicalKey: "develop", outcome: .known),
                VocabularyAssessmentAnswer(canonicalKey: "gaunt", outcome: .unknown)
            ],
            finalSelection: ["gaunt"]
        )

        store.save(session)
        XCTAssertEqual(store.load(), session)
        XCTAssertNil(VocabularyPreparationSessionStore(documentID: "document-b", defaults: defaults).load())
        store.clear()
        XCTAssertNil(store.load())
    }

    func testBatchImportRollsBackAllRecordsWhenOneInsertFails() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VocabularyPreparationRollback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("words.sqlite")
        let store = WordRecordSQLiteStore(databaseURL: databaseURL)

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, """
            CREATE TRIGGER reject_failed_preparation_word
            BEFORE INSERT ON web_word_records
            WHEN NEW.word = 'fail'
            BEGIN
              SELECT RAISE(ABORT, 'injected failure');
            END;
            """, nil, nil, nil), SQLITE_OK)

        let date = Date(timeIntervalSince1970: 1_000)
        let records = [
            webRecord(id: "one", word: "safe", date: date),
            webRecord(id: "two", word: "fail", date: date)
        ]
        XCTAssertFalse(store.upsertWebRecords(documentID: "document", records: records))
        XCTAssertTrue(store.loadWebRecords(documentID: "document").isEmpty)
    }

    private func webRecord(id: String, word: String, date: Date) -> StoredWebWordRecord {
        StoredWebWordRecord(
            id: id,
            vocabularyID: id,
            word: word,
            lemma: word,
            surfaceForm: word,
            context: "context",
            occurrenceIndex: nil,
            scrollProgress: 0.5,
            question: "",
            answer: "definition",
            createdAt: date,
            srs: VocabularySRSState.initial(createdAt: date)
        )
    }
}
