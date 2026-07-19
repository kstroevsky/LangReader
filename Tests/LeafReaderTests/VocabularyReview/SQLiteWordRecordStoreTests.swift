import Cocoa
import Foundation
import SQLite3

final class AIChatPanel {
    struct LinkedWordBubble {
        let id: String
        let word: String
        let question: String
        let answer: String
    }
}

private func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("SQLiteWordRecordStoreTests failed: \(message)\n", stderr)
        exit(1)
    }
}

private func pdfRecord(
    id: String,
    word: String,
    answer: String,
    createdAt: TimeInterval,
    srs: VocabularySRSState? = nil
) -> StoredPDFWordRecord {
    StoredPDFWordRecord(
        id: id,
        word: word,
        pageIndex: 4,
        bounds: StoredPDFWordRect(CGRect(x: 10, y: 20, width: 30, height: 12)),
        context: "pdf context",
        question: "What is \(word)?",
        answer: answer,
        createdAt: Date(timeIntervalSince1970: createdAt),
        srs: srs
    )
}

private func webRecord(
    id: String,
    word: String,
    answer: String,
    createdAt: TimeInterval,
    srs: VocabularySRSState? = nil
) -> StoredWebWordRecord {
    StoredWebWordRecord(
        id: id,
        word: word,
        context: "web context",
        occurrenceIndex: nil,
        scrollProgress: 0.42,
        question: "What is \(word)?",
        answer: answer,
        createdAt: Date(timeIntervalSince1970: createdAt),
        srs: srs
    )
}

@main
struct SQLiteWordRecordStoreTestRunner {
    static func main() {
        let dbDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("leafreader-production-sqlite-word-tests-\(UUID().uuidString)")
        let dbURL = dbDirectory.appendingPathComponent("word-records.sqlite3")
        let documentID = "sqlite-production-test-doc"
        let otherDocumentID = "sqlite-production-other-doc"
        let srs = VocabularySRSState(
            easeFactor: 2.6,
            intervalDays: 3,
            repetition: 2,
            dueDate: Date(timeIntervalSince1970: 20),
            lastReviewedAt: Date(timeIntervalSince1970: 10),
            reviewCount: 2,
            lapseCount: 1,
            activeRecallStreak: 2,
            masteredAt: nil
        )

        do {
        let store = WordRecordSQLiteStore(databaseURL: dbURL)
        let first = pdfRecord(id: "pdf-a", word: "alpha", answer: "one", createdAt: 1, srs: srs)
        let updated = pdfRecord(id: "pdf-a", word: "alpha", answer: "updated", createdAt: 2, srs: srs)
        let second = pdfRecord(id: "pdf-b", word: "beta", answer: "two", createdAt: 3)
        let other = pdfRecord(id: "pdf-other", word: "other", answer: "other", createdAt: 4)
        let batchBlank = pdfRecord(id: "pdf-c", word: "übersende", answer: "", createdAt: 5)
        let batchSecond = pdfRecord(id: "pdf-d", word: "Straße", answer: "", createdAt: 6)

        let defaultsSuite = "LeafVocabularyTests.PDFLocation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let locationStore = PDFWordRecordStore(fileMD5: documentID, defaults: defaults)
        let sameLocation = CGRect(x: 10.2, y: 20.2, width: 30.2, height: 12.2)
        assert(
            locationStore.existingRecord(in: [batchBlank], pageIndex: 4, bounds: sameLocation)?.id == batchBlank.id,
            "PDF occurrence deduplication should use rounded page-and-bounds location instead of record IDs"
        )
        assert(
            locationStore.existingRecord(in: [batchBlank], pageIndex: 5, bounds: sameLocation) == nil,
            "same bounds on different pages should remain separate occurrences"
        )

        assert(store.upsertPDFRecord(documentID: documentID, record: first), "PDF upsert should succeed")
        assert(store.upsertPDFRecord(documentID: otherDocumentID, record: other), "PDF upsert for another document should succeed")
        assert(store.upsertPDFRecord(documentID: documentID, record: second), "PDF second upsert should succeed")
        assert(store.upsertPDFRecord(documentID: documentID, record: updated), "PDF update upsert should succeed")

        let loadedPDF = store.loadPDFRecords(documentID: documentID)
        assert(loadedPDF.map(\.id) == ["pdf-a", "pdf-b"], "PDF records should load ordered records for one document only")
        assert(loadedPDF.first?.answer == "updated", "PDF upsert should replace existing rows")
        assert(loadedPDF.first?.srs?.reviewCount == 2, "PDF SRS state should round-trip through production SQLite store")
        assert(store.loadPDFRecords(documentID: otherDocumentID).map(\.id) == ["pdf-other"], "PDF records should stay scoped by document")

        assert(
            store.upsertPDFRecords(documentID: documentID, records: [batchBlank, batchSecond]),
            "PDF batch upsert should save all occurrences transactionally"
        )
        let loadedBatch = store.loadPDFRecords(documentID: documentID)
        assert(loadedBatch.map(\.id) == ["pdf-a", "pdf-b", "pdf-c", "pdf-d"], "PDF batch upsert should keep existing and new records")
        assert(loadedBatch.filter { ["pdf-c", "pdf-d"].contains($0.id) }.allSatisfy(\.answer.isEmpty), "answerless PDF records should round-trip")

        assert(store.deletePDFRecords(documentID: documentID, ids: ["pdf-a", "pdf-c", "pdf-d"]), "PDF delete(ids:) should succeed")
        assert(store.loadPDFRecords(documentID: documentID).map(\.id) == ["pdf-b"], "PDF delete(ids:) should remove only selected rows")

        let webFirst = webRecord(id: "web-a", word: "gamma", answer: "one", createdAt: 1, srs: srs)
        let webUpdated = webRecord(id: "web-a", word: "gamma", answer: "updated", createdAt: 2, srs: srs)
        let webSecond = webRecord(id: "web-b", word: "delta", answer: "two", createdAt: 3)
        assert(store.saveWebRecords(documentID: documentID, records: [webFirst, webSecond]), "Web full save should succeed")
        assert(store.upsertWebRecord(documentID: documentID, record: webUpdated), "Web upsert should succeed")

        let loadedWeb = store.loadWebRecords(documentID: documentID)
        assert(loadedWeb.map(\.id) == ["web-a", "web-b"], "Web records should load ordered records")
        assert(loadedWeb.first?.answer == "updated", "Web upsert should replace existing rows")
        assert(loadedWeb.first?.srs?.dueDate == Date(timeIntervalSince1970: 20), "Web SRS state should round-trip")
        assert(store.deleteWebRecords(documentID: documentID, ids: ["web-a"]), "Web delete(ids:) should succeed")
        assert(store.loadWebRecords(documentID: documentID).map(\.id) == ["web-b"], "Web delete(ids:) should remove only selected rows")

        let uniqueDocumentID = "sqlite-unique-word-doc"
        let uniqueFirst = StoredPDFWordRecord(
            id: "occurrence-one",
            word: "Fehlerhafte",
            lemma: "fehlerhaft",
            surfaceForm: "Fehlerhafte",
            pageIndex: 0,
            bounds: StoredPDFWordRect(CGRect(x: 12, y: 700, width: 60, height: 14)),
            context: "Eine fehlerhafte Lieferung.",
            question: "Definition: fehlerhaft",
            answer: "incorrect",
            createdAt: Date(timeIntervalSince1970: 7),
            srs: srs
        )
        let uniqueSecond = StoredPDFWordRecord(
            id: "occurrence-two",
            word: "fehlerhaften",
            lemma: "fehlerhaft",
            surfaceForm: "fehlerhaften",
            pageIndex: 5,
            bounds: StoredPDFWordRect(CGRect(x: 40, y: 500, width: 60, height: 14)),
            context: "Wegen eines fehlerhaften Eintrags.",
            question: "",
            answer: "",
            createdAt: Date(timeIntervalSince1970: 8),
            srs: srs
        )
        assert(
            store.upsertPDFRecords(documentID: uniqueDocumentID, records: [uniqueFirst, uniqueSecond]),
            "two occurrences of one Unicode word should save transactionally"
        )
        let uniqueLoaded = store.loadPDFRecords(documentID: uniqueDocumentID)
        assert(uniqueLoaded.count == 2, "one vocabulary word should retain both PDF occurrences")
        assert(Set(uniqueLoaded.compactMap(\.vocabularyID)).count == 1, "inflected forms should share one lemma vocabulary row")
        assert(Set(uniqueLoaded.map(\.word)) == ["Fehlerhafte"], "the first selected surface form should remain the shared display word")
        assert(Set(uniqueLoaded.map(\.occurrenceSurfaceForm)) == ["Fehlerhafte", "fehlerhaften"], "each occurrence should preserve its exact surface form")
        assert(uniqueLoaded.allSatisfy { $0.lemma == "fehlerhaft" }, "the German lemma should round-trip through SQLite")
        assert(uniqueLoaded.allSatisfy { $0.answer == "incorrect" }, "one definition should be shared by every inflected occurrence")
        assert(store.deletePDFRecords(documentID: uniqueDocumentID, ids: uniqueLoaded.map(\.id)), "deleting all occurrences should succeed")
        assert(store.loadPDFRecords(documentID: uniqueDocumentID).isEmpty, "deleting all occurrences should remove the orphaned word")
        }

        do {
        let reopened = WordRecordSQLiteStore(databaseURL: dbURL)
        assert(reopened.loadPDFRecords(documentID: documentID).map(\.id) == ["pdf-b"], "PDF records should persist after reopening production SQLite store")
        assert(reopened.loadWebRecords(documentID: documentID).map(\.id) == ["web-b"], "Web records should persist after reopening production SQLite store")
        }

        let legacyDBURL = dbDirectory.appendingPathComponent("legacy-word-records.sqlite3")
        createLegacyPDFDatabase(at: legacyDBURL)
        do {
            let migrated = WordRecordSQLiteStore(databaseURL: legacyDBURL).loadPDFRecords(documentID: "legacy-doc")
            assert(migrated.count == 2, "legacy occurrence rows should migrate without data loss")
            assert(Set(migrated.compactMap(\.vocabularyID)).count == 1, "legacy duplicate words should migrate into one canonical vocabulary row")
            assert(migrated.allSatisfy { $0.answer == "legacy definition" }, "legacy definitions should be shared after migration")
        }

        try? FileManager.default.removeItem(at: dbDirectory)
        print("SQLiteWordRecordStoreTests passed")
    }
}

private func createLegacyPDFDatabase(at url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var db: OpaquePointer?
    assert(sqlite3_open(url.path, &db) == SQLITE_OK, "legacy migration fixture should open")
    defer { sqlite3_close(db) }
    let sql = """
    CREATE TABLE pdf_word_records (
        document_id TEXT NOT NULL, id TEXT NOT NULL, word TEXT NOT NULL,
        page_index INTEGER NOT NULL, bounds_json TEXT NOT NULL, context TEXT,
        question TEXT NOT NULL, answer TEXT NOT NULL, dictionary_tags TEXT,
        dictionary_frequency INTEGER, created_at REAL NOT NULL, srs_json TEXT,
        PRIMARY KEY(document_id, id)
    );
    INSERT INTO pdf_word_records VALUES
      ('legacy-doc','legacy-a','Straße',0,'{"x":10,"y":20,"width":40,"height":12}','erste Stelle','','',NULL,NULL,1,NULL),
      ('legacy-doc','legacy-b','straße',3,'{"x":15,"y":25,"width":40,"height":12}','zweite Stelle','Definition','legacy definition',NULL,NULL,2,NULL);
    """
    assert(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, "legacy migration fixture should be created")
}
