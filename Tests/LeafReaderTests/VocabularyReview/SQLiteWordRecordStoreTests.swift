import Cocoa
import Foundation
import SQLite3
import LeafReaderCore

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
        // This file builds as its own binary and cannot see the shared helper in
        // `Support/LogicTests.swift`, so the same cleanup is spelled out here:
        // removing the domain leaves an empty plist behind unless the file goes
        // too.
        defer {
            defaults.removePersistentDomain(forName: defaultsSuite)
            let plist = FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/\(defaultsSuite).plist")
            try? FileManager.default.removeItem(at: plist)
        }
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

        // MARK: - German flexion cache

        do {
            let flexionDBURL = dbDirectory.appendingPathComponent("flexion.sqlite3")
            let store = WordRecordSQLiteStore(databaseURL: flexionDBURL)
            let flexion = GermanFlexionStore(store: store)

            assert(!flexion.hasEntry(forLemma: "Haus"), "an unfetched lemma should not be cached")

            let saved = flexion.save(
                StoredGermanFlexion(
                    lemma: "Haus",
                    genus: "n",
                    auxiliary: nil,
                    forms: [
                        StoredGermanFlexionForm(parameter: "Nominativ Singular", surface: "Haus", isVariant: false),
                        StoredGermanFlexionForm(parameter: "Nominativ Plural", surface: "Häuser", isVariant: false),
                        StoredGermanFlexionForm(parameter: "Dativ Singular", surface: "Hause", isVariant: true)
                    ],
                    fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
                )
            )
            assert(saved, "a flexion table should persist")
            assert(flexion.hasEntry(forLemma: "Haus"), "a saved lemma should be reported as cached")
            assert(flexion.hasEntry(forLemma: "haus"), "cache lookups should be case-insensitive")

            let matches = flexion.matches(surfaceForm: "Häuser")
            assert(matches.count == 1, "the plural should resolve to exactly one cached form")
            assert(matches.first?.lemma == "Haus", "the reverse lookup should recover the lemma")
            assert(matches.first?.parameter == "Nominativ Plural", "the parameter should round-trip")

            // The gap this whole tier exists to close: 'Häuser' never reduces
            // to 'Haus' offline, so grouping depends on this reverse lookup.
            assert(flexion.lemma(forSurfaceForm: "Häuser") == "Haus", "Häuser should resolve to Haus")
            assert(flexion.lemma(forSurfaceForm: "häuser") == "Haus", "reverse lookup should ignore case")
            assert(flexion.lemma(forSurfaceForm: "Hunde") == nil, "an unknown form should resolve to no lemma")

            // A variant spelling should report its lemma, not itself.
            assert(flexion.lemma(forSurfaceForm: "Hause") == "Haus", "a variant form should resolve to its lemma")

            // Re-saving replaces rather than duplicating.
            _ = flexion.save(
                StoredGermanFlexion(
                    lemma: "Haus",
                    genus: "n",
                    auxiliary: nil,
                    forms: [
                        StoredGermanFlexionForm(parameter: "Nominativ Plural", surface: "Häuser", isVariant: false)
                    ],
                    fetchedAt: Date(timeIntervalSince1970: 1_700_000_100)
                )
            )
            assert(
                flexion.matches(surfaceForm: "Hause").isEmpty,
                "re-saving a lemma should drop forms that are no longer present"
            )
            assert(
                flexion.matches(surfaceForm: "Häuser").count == 1,
                "re-saving should not duplicate retained forms"
            )

            // A lemma with no table is still recorded, so it is not refetched.
            _ = flexion.save(
                StoredGermanFlexion(
                    lemma: "Xyzzyx",
                    genus: nil,
                    auxiliary: nil,
                    forms: [],
                    fetchedAt: Date(timeIntervalSince1970: 1_700_000_200)
                )
            )
            assert(
                flexion.hasEntry(forLemma: "Xyzzyx"),
                "a lemma with no flexion table should still be marked as fetched"
            )

            // Persistence must survive reopening the database.
            let reopened = GermanFlexionStore(store: WordRecordSQLiteStore(databaseURL: flexionDBURL))
            assert(
                reopened.lemma(forSurfaceForm: "Häuser") == "Haus",
                "cached flexion data should survive a reopen, so it works offline later"
            )
        }

        // MARK: - German form-label cache

        do {
            let labelDBURL = dbDirectory.appendingPathComponent("form-labels.sqlite3")
            let store = WordRecordSQLiteStore(databaseURL: labelDBURL)

            assert(
                store.germanFormLabel(surfaceKey: "gekommen", lemmaKey: "kommen", version: 1) == nil,
                "an unlabeled pair should be a cache miss"
            )

            assert(
                store.saveGermanFormLabel(surfaceKey: "gekommen", lemmaKey: "kommen", label: "partizipII", version: 1),
                "saving a label should succeed"
            )
            assert(
                store.germanFormLabel(surfaceKey: "gekommen", lemmaKey: "kommen", version: 1)?.label == "partizipII",
                "a cached label should round-trip"
            )

            // "No label" is stored distinctly from a miss, so an ambiguous form
            // proven to have no label is not recomputed on every open.
            assert(
                store.saveGermanFormLabel(surfaceKey: "autos", lemmaKey: "auto", label: nil, version: 1),
                "saving a nil label should succeed"
            )
            let nilHit = store.germanFormLabel(surfaceKey: "autos", lemmaKey: "auto", version: 1)
            assert(nilHit != nil, "a proven-unlabelable pair should be a cache hit, not a miss")
            assert(nilHit?.label == nil, "the cache hit should carry no label")

            // A label written by a different labeler version is treated as absent.
            assert(
                store.germanFormLabel(surfaceKey: "gekommen", lemmaKey: "kommen", version: 2) == nil,
                "a superseded labeler version should invalidate cached labels"
            )

            // Explicit lemma invalidation drops that lemma's labels only.
            assert(store.deleteGermanFormLabels(lemmaKey: "kommen"), "deleting a lemma's labels should succeed")
            assert(
                store.germanFormLabel(surfaceKey: "gekommen", lemmaKey: "kommen", version: 1) == nil,
                "deleting a lemma's labels should remove them"
            )
            assert(
                store.germanFormLabel(surfaceKey: "autos", lemmaKey: "auto", version: 1) != nil,
                "deleting one lemma's labels must not touch another lemma"
            )

            // A cached label is the flexion-independent offline verdict, so
            // saving a flexion table leaves it untouched — the refinement is
            // composed fresh on read rather than baked into the cache, which is
            // why no invalidation (and no racy delete) is needed here.
            _ = store.saveGermanFormLabel(surfaceKey: "gab", lemmaKey: "geben", label: "finiteVerb", version: 1)
            _ = GermanFlexionStore(store: store).save(
                StoredGermanFlexion(
                    lemma: "geben",
                    genus: nil,
                    auxiliary: "haben",
                    forms: [StoredGermanFlexionForm(parameter: "Präteritum ich", surface: "gab", isVariant: false)],
                    fetchedAt: Date(timeIntervalSince1970: 1_700_000_300)
                )
            )
            assert(
                store.germanFormLabel(surfaceKey: "gab", lemmaKey: "geben", version: 1)?.label == "finiteVerb",
                "saving a flexion table must not disturb the cached offline label"
            )

            // Persistence across reopen.
            let reopened = WordRecordSQLiteStore(databaseURL: labelDBURL)
            assert(
                reopened.germanFormLabel(surfaceKey: "autos", lemmaKey: "auto", version: 1)?.label == nil,
                "a cached nil label should survive a reopen"
            )
        }

        // MARK: - Regrouping inflected records onto their lemma

        // Case 1: no record exists under the lemma, so the row is re-keyed.
        do {
            let url = dbDirectory.appendingPathComponent("regroup-rekey.sqlite3")
            let store = WordRecordSQLiteStore(databaseURL: url)
            var inflected = pdfRecord(id: "a", word: "Häuser", answer: "houses", createdAt: 10)
            inflected.lemma = "Häuser"
            _ = store.savePDFRecords(documentID: "doc", records: [inflected])

            let moved = store.regroupVocabulary(fromKey: "häuser", intoKey: "haus", lemma: "Haus")
            assert(moved == 1, "an inflected record should be re-keyed onto its lemma")

            let loaded = store.loadPDFRecords(documentID: "doc")
            assert(loaded.count == 1, "re-keying must not duplicate the record")
            assert(loaded.first?.lemma == "Haus", "the lemma column should be updated")
            assert(loaded.first?.word == "Häuser", "the saved spelling should be preserved")
            assert(loaded.first?.answer == "houses", "the answer must survive re-keying")

            // Idempotent: running again finds nothing to move.
            assert(
                store.regroupVocabulary(fromKey: "häuser", intoKey: "haus", lemma: "Haus") == 0,
                "regrouping should be idempotent"
            )
        }

        // Case 2: a record already exists under the lemma, forcing a merge
        // rather than a re-key, because canonical_key is UNIQUE per document.
        do {
            let url = dbDirectory.appendingPathComponent("regroup-merge.sqlite3")
            let store = WordRecordSQLiteStore(databaseURL: url)
            var base = pdfRecord(id: "base", word: "Haus", answer: "", createdAt: 100)
            base.lemma = "Haus"
            // A different page, so the two occurrences cannot collide on
            // location and the merge is testing the word rows, not dedup.
            let inflected = StoredPDFWordRecord(
                id: "infl",
                word: "Häuser",
                lemma: "Häuser",
                pageIndex: 7,
                bounds: StoredPDFWordRect(CGRect(x: 5, y: 6, width: 7, height: 8)),
                context: "andere Stelle",
                question: "q",
                answer: "a house",
                createdAt: Date(timeIntervalSince1970: 50),
                srs: nil
            )
            _ = store.savePDFRecords(documentID: "doc", records: [base, inflected])
            assert(
                store.loadPDFRecords(documentID: "doc").count == 2,
                "the two spellings should start as separate records"
            )

            let moved = store.regroupVocabulary(fromKey: "häuser", intoKey: "haus", lemma: "Haus")
            assert(moved == 1, "the inflected record should merge into the lemma record")

            let loaded = store.loadPDFRecords(documentID: "doc")
            assert(loaded.count == 2, "both occurrences should survive the merge")
            assert(
                Set(loaded.compactMap(\.vocabularyID)).count == 1,
                "the two records should collapse onto one vocabulary row"
            )
            assert(
                loaded.allSatisfy { $0.answer == "a house" },
                "an empty answer should adopt the merged record's answer rather than lose it"
            )
            // created_at on the vocabulary row is not surfaced by loadPDFRecords,
            // which reports each occurrence's own timestamp, so read it directly.
            assert(
                vocabularyCreatedAt(at: url, documentID: "doc", canonicalKey: "haus") == 50,
                "the surviving vocabulary row should keep the earlier creation date"
            )
        }

        // Case 3: the occurrences of both records survive the merge.
        do {
            let url = dbDirectory.appendingPathComponent("regroup-occurrences.sqlite3")
            let store = WordRecordSQLiteStore(databaseURL: url)
            var base = pdfRecord(id: "base", word: "Haus", answer: "house", createdAt: 100)
            base.lemma = "Haus"
            // Distinct pages, so no occurrence is a duplicate of another.
            let other = StoredPDFWordRecord(
                id: "infl",
                word: "Häuser",
                lemma: "Häuser",
                pageIndex: 8,
                bounds: StoredPDFWordRect(CGRect(x: 1, y: 2, width: 3, height: 4)),
                context: "eine Stelle",
                question: "q",
                answer: "houses",
                createdAt: Date(timeIntervalSince1970: 50),
                srs: nil
            )
            let otherElsewhere = StoredPDFWordRecord(
                id: "infl2",
                word: "Häuser",
                lemma: "Häuser",
                pageIndex: 9,
                bounds: StoredPDFWordRect(CGRect(x: 5, y: 6, width: 7, height: 8)),
                context: "andere Stelle",
                question: "q",
                answer: "houses",
                createdAt: Date(timeIntervalSince1970: 60),
                srs: nil
            )
            _ = store.savePDFRecords(documentID: "doc", records: [base, other, otherElsewhere])

            let before = store.loadPDFRecords(documentID: "doc").count
            _ = store.regroupVocabulary(fromKey: "häuser", intoKey: "haus", lemma: "Haus")
            let after = store.loadPDFRecords(documentID: "doc")
            assert(before == 3, "three occurrences should exist before the merge")
            assert(after.count == 3, "occurrences at distinct locations must all survive the merge")
            assert(
                Set(after.compactMap(\.vocabularyID)).count == 1,
                "all occurrences should end up under one vocabulary row"
            )
            assert(
                Set(after.map(\.pageIndex)) == [4, 8, 9],
                "each original page should still be reachable after the merge"
            )
        }

        // Case 3b: two occurrences at the identical location are the same
        // physical word, so the merge collapses them instead of duplicating.
        do {
            let url = dbDirectory.appendingPathComponent("regroup-duplicate-location.sqlite3")
            let store = WordRecordSQLiteStore(databaseURL: url)
            var base = pdfRecord(id: "base", word: "Haus", answer: "house", createdAt: 100)
            base.lemma = "Haus"
            var sameSpot = pdfRecord(id: "infl", word: "Häuser", answer: "houses", createdAt: 50)
            sameSpot.lemma = "Häuser"
            _ = store.savePDFRecords(documentID: "doc", records: [base, sameSpot])
            assert(store.loadPDFRecords(documentID: "doc").count == 2, "both start out present")

            _ = store.regroupVocabulary(fromKey: "häuser", intoKey: "haus", lemma: "Haus")
            let after = store.loadPDFRecords(documentID: "doc")
            assert(
                after.count == 1,
                "occurrences sharing one location should collapse rather than duplicate"
            )
        }

        // Case 4: guards.
        do {
            let url = dbDirectory.appendingPathComponent("regroup-guards.sqlite3")
            let store = WordRecordSQLiteStore(databaseURL: url)
            var record = pdfRecord(id: "a", word: "Haus", answer: "house", createdAt: 10)
            record.lemma = "Haus"
            _ = store.savePDFRecords(documentID: "doc", records: [record])

            assert(
                store.regroupVocabulary(fromKey: "haus", intoKey: "haus", lemma: "Haus") == 0,
                "regrouping a key onto itself should be a no-op"
            )
            assert(
                store.regroupVocabulary(fromKey: "", intoKey: "haus", lemma: "Haus") == 0,
                "an empty source key should be rejected"
            )
            assert(
                store.regroupVocabulary(fromKey: "unbekannt", intoKey: "haus", lemma: "Haus") == 0,
                "an unknown source key should move nothing"
            )
            assert(
                store.loadPDFRecords(documentID: "doc").count == 1,
                "guarded calls must leave the data untouched"
            )
        }

        // Case 5: a spelling claimed by two lemmas is left alone.
        do {
            let url = dbDirectory.appendingPathComponent("regroup-ambiguous.sqlite3")
            let store = WordRecordSQLiteStore(databaseURL: url)
            let flexion = GermanFlexionStore(store: store)
            var record = pdfRecord(id: "a", word: "Steuer", answer: "", createdAt: 10)
            record.lemma = "Steuer"
            _ = store.savePDFRecords(documentID: "doc", records: [record])

            // Two different lemmas both listing 'Steuer' as a form.
            _ = flexion.save(StoredGermanFlexion(
                lemma: "Steuermann", genus: "m", auxiliary: nil,
                forms: [StoredGermanFlexionForm(parameter: "Nominativ Singular", surface: "Steuer", isVariant: false)],
                fetchedAt: Date(timeIntervalSince1970: 1)
            ))
            let second = StoredGermanFlexion(
                lemma: "Steuerung", genus: "f", auxiliary: nil,
                forms: [StoredGermanFlexionForm(parameter: "Nominativ Singular", surface: "Steuer", isVariant: false)],
                fetchedAt: Date(timeIntervalSince1970: 2)
            )
            _ = flexion.save(second)

            assert(
                flexion.lemma(forSurfaceForm: "Steuer") == nil,
                "a spelling claimed by two lemmas should resolve to neither"
            )
            assert(
                flexion.regroupSavedVocabulary(for: second) == 0,
                "an ambiguous spelling must not be merged into either lemma"
            )
            assert(
                store.loadPDFRecords(documentID: "doc").first?.word == "Steuer",
                "the ambiguous record should be left exactly as it was"
            )
        }

        try? FileManager.default.removeItem(at: dbDirectory)
        print("SQLiteWordRecordStoreTests passed")
    }
}

/// Reads `pdf_vocabulary_words.created_at` directly, since `loadPDFRecords`
/// surfaces each occurrence's timestamp rather than the vocabulary row's.
private func vocabularyCreatedAt(at url: URL, documentID: String, canonicalKey: String) -> Double? {
    var db: OpaquePointer?
    guard sqlite3_open(url.path, &db) == SQLITE_OK else { return nil }
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    let sql = "SELECT created_at FROM pdf_vocabulary_words WHERE document_id = ? AND canonical_key = ?"
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
    defer { sqlite3_finalize(statement) }
    sqlite3_bind_text(statement, 1, (documentID as NSString).utf8String, -1, nil)
    sqlite3_bind_text(statement, 2, (canonicalKey as NSString).utf8String, -1, nil)
    guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
    return sqlite3_column_double(statement, 0)
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
