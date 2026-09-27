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
    language: VocabularyLanguageID? = nil,
    textAnchor: TextQuoteAnchor? = nil,
    bounds: CGRect = CGRect(x: 10, y: 20, width: 30, height: 12),
    srs: VocabularySRSState? = nil
) -> StoredPDFWordRecord {
    StoredPDFWordRecord(
        id: id,
        word: word,
        language: language,
        pageIndex: 4,
        bounds: StoredPDFWordRect(bounds),
        textAnchor: textAnchor,
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
    vocabularyID: String? = nil,
    language: VocabularyLanguageID? = nil,
    lemma: String? = nil,
    lexicalKey: String? = nil,
    partOfSpeech: VocabularyPartOfSpeech? = nil,
    surfaceForm: String? = nil,
    srs: VocabularySRSState? = nil
) -> StoredWebWordRecord {
    StoredWebWordRecord(
        id: id,
        vocabularyID: vocabularyID,
        word: word,
        language: language,
        lemma: lemma,
        lexicalKey: lexicalKey,
        partOfSpeech: partOfSpeech,
        surfaceForm: surfaceForm,
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
        let anchor = TextQuoteAnchor(
            unitOrdinal: 4,
            sourceRange: NSRange(location: 6, length: 5),
            sourceText: "Start alpha end"
        )
        assert(anchor?.exactQuote == "alpha", "semantic anchors should retain the exact quote")
        assert(anchor?.prefix == "Start ", "semantic anchors should retain bounded prefix context")
        assert(anchor?.suffix == " end", "semantic anchors should retain bounded suffix context")
        let first = pdfRecord(id: "pdf-a", word: "alpha", answer: "one", createdAt: 1, language: .english, textAnchor: anchor, srs: srs)
        let updated = pdfRecord(id: "pdf-a", word: "alpha", answer: "updated", createdAt: 2, language: .english, textAnchor: anchor, srs: srs)
        let second = pdfRecord(id: "pdf-b", word: "beta", answer: "two", createdAt: 3)
        let other = pdfRecord(id: "pdf-other", word: "other", answer: "other", createdAt: 4)
        let batchBlank = pdfRecord(
            id: "pdf-c",
            word: "übersende",
            answer: "",
            createdAt: 5,
            bounds: CGRect(x: 50, y: 20, width: 30, height: 12)
        )
        let batchSecond = pdfRecord(
            id: "pdf-d",
            word: "Straße",
            answer: "",
            createdAt: 6,
            bounds: CGRect(x: 90, y: 20, width: 30, height: 12)
        )

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
        assert(locationStore.needsMetadataRepair, "PDF metadata repair should run once for an unversioned document")
        locationStore.markMetadataRepairCompleted()
        assert(!locationStore.needsMetadataRepair, "PDF metadata repair should be skipped after its version is recorded")
        assert(
            PDFWordRecordStore(fileMD5: otherDocumentID, defaults: defaults).needsMetadataRepair,
            "metadata repair versions should remain document-scoped"
        )
        let sameLocation = CGRect(x: 50.2, y: 20.2, width: 30.2, height: 12.2)
        assert(
            locationStore.existingRecord(in: [batchBlank], pageIndex: 4, bounds: sameLocation)?.id == batchBlank.id,
            "PDF occurrence deduplication should use rounded page-and-bounds location instead of record IDs"
        )
        assert(
            locationStore.existingRecord(in: [batchBlank], pageIndex: 5, bounds: sameLocation) == nil,
            "same bounds on different pages should remain separate occurrences"
        )
        let unresolvedSemantic = pdfRecord(
            id: "semantic-unresolved",
            word: "alpha",
            answer: "",
            createdAt: 1,
            textAnchor: anchor,
            bounds: .zero
        )
        assert(
            locationStore.recordKey(record: unresolvedSemantic) == "text:4:6:5",
            "semantic occurrence identity should not depend on resolved geometry"
        )
        assert(
            locationStore.existingRecord(
                in: [unresolvedSemantic],
                pageIndex: 4,
                bounds: sameLocation,
                textAnchor: anchor
            )?.id == unresolvedSemantic.id,
            "semantic selection deduplication should work before geometry is resolved"
        )

        assert(store.upsertPDFRecord(documentID: documentID, record: first), "PDF upsert should succeed")
        assert(store.upsertPDFRecord(documentID: otherDocumentID, record: other), "PDF upsert for another document should succeed")
        assert(store.upsertPDFRecord(documentID: documentID, record: second), "PDF second upsert should succeed")
        assert(store.upsertPDFRecord(documentID: documentID, record: updated), "PDF update upsert should succeed")

        let loadedPDF = store.loadPDFRecords(documentID: documentID)
        assert(loadedPDF.map(\.id) == ["pdf-a", "pdf-b"], "PDF records should load ordered records for one document only")
        assert(loadedPDF.first?.answer == "updated", "PDF upsert should replace existing rows")
        assert(loadedPDF.first?.language == .english, "PDF language identity should round-trip through production SQLite store")
        assert(loadedPDF.first?.textAnchor == anchor, "PDF semantic text anchors should round-trip through production SQLite store")
        assert(loadedPDF.first?.srs?.reviewCount == 2, "PDF SRS state should round-trip through production SQLite store")
        assert(store.loadPDFRecords(documentID: otherDocumentID).map(\.id) == ["pdf-other"], "PDF records should stay scoped by document")

        let semanticDocumentID = "sqlite-semantic-location-doc"
        let movedOccurrence = pdfRecord(
            id: "semantic-first",
            word: "alpha",
            answer: "one",
            createdAt: 1,
            textAnchor: anchor
        )
        let relaidOccurrence = pdfRecord(
            id: "semantic-second",
            word: "alpha",
            answer: "one",
            createdAt: 2,
            textAnchor: anchor,
            bounds: CGRect(x: 180, y: 420, width: 70, height: 18)
        )
        assert(
            store.upsertPDFRecords(documentID: semanticDocumentID, records: [movedOccurrence, relaidOccurrence]),
            "semantic occurrence upsert should succeed across changed geometry"
        )
        let semanticOccurrences = store.loadPDFRecords(documentID: semanticDocumentID)
        assert(semanticOccurrences.map(\.id) == ["semantic-first"], "one semantic anchor should preserve its original occurrence UUID after geometry changes")

        let unresolvedDocumentID = "sqlite-unresolved-semantic-doc"
        assert(
            store.upsertPDFRecord(documentID: unresolvedDocumentID, record: unresolvedSemantic),
            "an offscreen semantic occurrence should persist without geometry"
        )
        let loadedUnresolved = store.loadPDFRecords(documentID: unresolvedDocumentID)
        assert(loadedUnresolved.first?.bounds.cgRect == .zero, "unresolved geometry should round-trip as a lazy cache sentinel")
        assert(loadedUnresolved.first?.textAnchor == anchor, "the semantic anchor should remain authoritative without bounds")

        assert(
            store.upsertPDFRecords(documentID: documentID, records: [batchBlank, batchSecond]),
            "PDF batch upsert should save all occurrences transactionally"
        )
        let loadedBatch = store.loadPDFRecords(documentID: documentID)
        assert(loadedBatch.map(\.id) == ["pdf-a", "pdf-b", "pdf-c", "pdf-d"], "PDF batch upsert should keep existing and new records")
        assert(loadedBatch.filter { ["pdf-c", "pdf-d"].contains($0.id) }.allSatisfy(\.answer.isEmpty), "answerless PDF records should round-trip")

        assert(store.deletePDFRecords(documentID: documentID, ids: ["pdf-a", "pdf-c", "pdf-d"]), "PDF delete(ids:) should succeed")
        assert(store.loadPDFRecords(documentID: documentID).map(\.id) == ["pdf-b"], "PDF delete(ids:) should remove only selected rows")

        let webFirst = webRecord(
            id: "web-a",
            word: "ging",
            answer: "one",
            createdAt: 1,
            vocabularyID: "web-vocabulary-go",
            language: .german,
            lemma: "gehen",
            lexicalKey: "de|gehen|verb|",
            partOfSpeech: .verb,
            surfaceForm: "ging",
            srs: srs
        )
        let webUpdated = webRecord(
            id: "web-a",
            word: "ging",
            answer: "updated",
            createdAt: 2,
            vocabularyID: "web-vocabulary-go",
            language: .german,
            lemma: "gehen",
            lexicalKey: "de|gehen|verb|",
            partOfSpeech: .verb,
            surfaceForm: "Ging",
            srs: srs
        )
        let webSecond = webRecord(id: "web-b", word: "delta", answer: "two", createdAt: 3)
        assert(store.saveWebRecords(documentID: documentID, records: [webFirst, webSecond]), "Web full save should succeed")
        assert(store.upsertWebRecord(documentID: documentID, record: webUpdated), "Web upsert should succeed")

        let loadedWeb = store.loadWebRecords(documentID: documentID)
        assert(loadedWeb.map(\.id) == ["web-a", "web-b"], "Web records should load ordered records")
        assert(loadedWeb.first?.answer == "updated", "Web upsert should replace existing rows")
        assert(loadedWeb.first?.vocabularyID == "web-vocabulary-go", "Web vocabulary identity should round-trip")
        assert(loadedWeb.first?.language == .german, "Web language identity should round-trip")
        assert(loadedWeb.first?.lemma == "gehen", "Web lemma should round-trip")
        assert(loadedWeb.first?.lexicalKey == "de|gehen|verb|", "Web lexical key should round-trip")
        assert(loadedWeb.first?.partOfSpeech == .verb, "Web part of speech should round-trip")
        assert(loadedWeb.first?.occurrenceSurfaceForm == "Ging", "Web surface form should round-trip exactly")
        assert(loadedWeb.first?.srs?.dueDate == Date(timeIntervalSince1970: 20), "Web SRS state should round-trip")
        let unresolvedWeb = loadedWeb.first { $0.id == "web-b" }
        assert(unresolvedWeb?.vocabularyID == nil, "legacy Web rows must not gain a vocabulary owner during storage round-trip")
        assert(unresolvedWeb?.language == nil, "legacy Web rows must remain language-unresolved without explicit evidence")
        assert(unresolvedWeb?.lemma == nil, "legacy Web rows must not gain an inferred lemma during storage round-trip")
        assert(unresolvedWeb?.lexicalKey == nil, "legacy Web rows must not gain a lexical identity during storage round-trip")
        assert(unresolvedWeb?.partOfSpeech == nil, "legacy Web rows must not gain inferred part of speech during storage round-trip")
        assert(unresolvedWeb?.surfaceForm == nil, "legacy Web rows must preserve nullable surface metadata during storage round-trip")
        assert(unresolvedWeb?.answer == "two", "legacy Web answers must survive unresolved storage round-trip")

        assert(store.deleteWebRecords(documentID: documentID, ids: ["web-a"]), "Web delete(ids:) should succeed")
        assert(store.loadWebRecords(documentID: documentID).map(\.id) == ["web-b"], "Web delete(ids:) should remove only selected rows")

        let uniqueDocumentID = "sqlite-unique-word-doc"
        let uniqueFirst = StoredPDFWordRecord(
            id: "occurrence-one",
            word: "Fehlerhafte",
            lemma: "fehlerhaft",
            lexicalKey: "de|fehlerhaft|adjective|",
            partOfSpeech: .adjective,
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
            lexicalKey: "de|fehlerhaft|adjective|",
            partOfSpeech: .adjective,
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
        assert(uniqueLoaded.allSatisfy { $0.lexicalKey == "de|fehlerhaft|adjective|" }, "the PDF lexical key should round-trip")
        assert(uniqueLoaded.allSatisfy { $0.partOfSpeech == .adjective }, "the PDF part of speech should round-trip")
        assert(uniqueLoaded.allSatisfy { $0.answer == "incorrect" }, "one definition should be shared by every inflected occurrence")
        assert(store.deletePDFRecords(documentID: uniqueDocumentID, ids: uniqueLoaded.map(\.id)), "deleting all occurrences should succeed")
        assert(store.loadPDFRecords(documentID: uniqueDocumentID).isEmpty, "deleting all occurrences should remove the orphaned word")

        // ADR-0002 §59: enriching one occurrence of a legacy shared owner must
        // keep the original occurrence and learning owner while storing the new
        // linguistic evidence on that occurrence.
        let sharedOwnerURL = dbDirectory.appendingPathComponent("legacy-shared-owner.sqlite3")
        let sharedOwnerDocumentID = "legacy-shared-owner-doc"
        let sharedSource = "lief lief lief"
        let sharedFirstAnchor = TextQuoteAnchor(
            unitOrdinal: 0,
            sourceRange: NSRange(location: 0, length: 4),
            sourceText: sharedSource
        )!
        let sharedSecondAnchor = TextQuoteAnchor(
            unitOrdinal: 0,
            sourceRange: NSRange(location: 5, length: 4),
            sourceText: sharedSource
        )!
        let sharedThirdAnchor = TextQuoteAnchor(
            unitOrdinal: 0,
            sourceRange: NSRange(location: 10, length: 4),
            sourceText: sharedSource
        )!
        do {
            let sharedStore = WordRecordSQLiteStore(databaseURL: sharedOwnerURL)
            let legacyFirst = pdfRecord(
                id: "legacy-occurrence-a",
                word: "lief",
                answer: "ran",
                createdAt: 30,
                textAnchor: sharedFirstAnchor,
                srs: srs
            )
            let legacySecond = pdfRecord(
                id: "legacy-occurrence-b",
                word: "lief",
                answer: "ran",
                createdAt: 31,
                textAnchor: sharedSecondAnchor,
                srs: srs
            )
            assert(
                sharedStore.savePDFRecords(
                    documentID: sharedOwnerDocumentID,
                    records: [legacyFirst, legacySecond]
                ),
                "legacy shared-owner fixture should save"
            )
            let legacyLoaded = sharedStore.loadPDFRecords(documentID: sharedOwnerDocumentID)
            assert(legacyLoaded.count == 2, "legacy shared-owner fixture should retain both occurrences")
            let legacyOwnerIDs = Set(legacyLoaded.compactMap(\.vocabularyID))
            assert(legacyOwnerIDs.count == 1, "legacy occurrences should begin under one learning owner")
            let legacyOwnerID = legacyOwnerIDs.first!

            let enriched = StoredPDFWordRecord(
                id: "legacy-occurrence-a",
                vocabularyID: legacyOwnerID,
                word: "lief",
                language: .german,
                lemma: "laufen",
                lexicalKey: "de|laufen|verb|",
                partOfSpeech: .verb,
                surfaceForm: "lief",
                pageIndex: 4,
                bounds: legacyFirst.bounds,
                textAnchor: sharedFirstAnchor,
                context: legacyFirst.context,
                question: "stale enrichment question",
                answer: "stale enrichment answer",
                createdAt: legacyFirst.createdAt,
                srs: VocabularySRSState.initial(createdAt: legacyFirst.createdAt)
            )
            assert(
                sharedStore.upsertPDFRecord(documentID: sharedOwnerDocumentID, record: enriched),
                "legacy occurrence enrichment should succeed"
            )
            var afterEnrichment = sharedStore.loadPDFRecords(documentID: sharedOwnerDocumentID)
            let enrichedLoaded = afterEnrichment.first { $0.id == "legacy-occurrence-a" }
            let untouchedLoaded = afterEnrichment.first { $0.id == "legacy-occurrence-b" }
            assert(enrichedLoaded?.vocabularyID == legacyOwnerID, "enrichment must preserve the legacy learning owner")
            assert(untouchedLoaded?.vocabularyID == legacyOwnerID, "enrichment must not split the shared learning owner")
            assert(enrichedLoaded?.language == .german, "enrichment should persist occurrence language")
            assert(enrichedLoaded?.lexicalKey == "de|laufen|verb|", "enrichment should persist occurrence lexical identity")
            assert(enrichedLoaded?.partOfSpeech == .verb, "enrichment should persist occurrence POS")
            assert(untouchedLoaded?.lexicalKey == nil, "enriching one occurrence must not relabel its sibling")
            assert(afterEnrichment.allSatisfy { $0.answer == "ran" }, "enrichment must preserve the shared answer")
            assert(afterEnrichment.allSatisfy { $0.srs?.reviewCount == 2 }, "enrichment must preserve shared SRS history")

            let retryWithFreshID = StoredPDFWordRecord(
                id: "fresh-retry-id",
                vocabularyID: "candidate-new-owner",
                word: "lief",
                language: .german,
                lemma: "laufen",
                lexicalKey: "de|laufen|verb|",
                partOfSpeech: .verb,
                surfaceForm: "lief",
                pageIndex: 4,
                bounds: legacyFirst.bounds,
                textAnchor: sharedFirstAnchor,
                context: legacyFirst.context,
                question: "retry question",
                answer: "retry answer",
                createdAt: Date(timeIntervalSince1970: 40),
                srs: VocabularySRSState.initial(createdAt: Date(timeIntervalSince1970: 40))
            )
            assert(
                sharedStore.upsertPDFRecord(documentID: sharedOwnerDocumentID, record: retryWithFreshID),
                "fresh-ID retry for the same stable source occurrence should succeed"
            )
            afterEnrichment = sharedStore.loadPDFRecords(documentID: sharedOwnerDocumentID)
            assert(afterEnrichment.count == 2, "fresh-ID retry must not duplicate the occurrence")
            assert(Set(afterEnrichment.map(\.id)) == ["legacy-occurrence-a", "legacy-occurrence-b"], "fresh-ID retry must preserve the original occurrence UUID")
            assert(afterEnrichment.allSatisfy { $0.vocabularyID == legacyOwnerID }, "fresh-ID retry must preserve the learning owner")
            assert(afterEnrichment.allSatisfy { $0.answer == "ran" }, "fresh-ID retry must not overwrite the shared answer")
            assert(afterEnrichment.allSatisfy { $0.srs?.reviewCount == 2 }, "fresh-ID retry must not overwrite shared SRS")

            var reviewed = afterEnrichment.first { $0.id == "legacy-occurrence-a" }!
            reviewed.answer = "ran; sprinted"
            reviewed.srs = reviewed.srs?.reviewed(grade: 3, at: Date(timeIntervalSince1970: 50))
            assert(
                sharedStore.upsertPDFRecord(documentID: sharedOwnerDocumentID, record: reviewed),
                "review update should remain writable through the preserved learning owner"
            )
            let afterReview = sharedStore.loadPDFRecords(documentID: sharedOwnerDocumentID)
            assert(afterReview.allSatisfy { $0.answer == "ran; sprinted" }, "shared-owner answer edits should remain shared")
            assert(afterReview.allSatisfy { $0.srs?.reviewCount == 3 }, "shared-owner review should score the owner once")

            var undone = afterReview.first { $0.id == "legacy-occurrence-a" }!
            undone.answer = "ran"
            undone.srs = srs
            assert(
                sharedStore.upsertPDFRecord(documentID: sharedOwnerDocumentID, record: undone),
                "undo should remain writable through the preserved learning owner"
            )

            let resolvedNewOccurrence = StoredPDFWordRecord(
                id: "resolved-new-occurrence",
                vocabularyID: legacyOwnerID,
                word: "lief",
                language: .german,
                lemma: "laufen",
                lexicalKey: "de|laufen|verb|",
                partOfSpeech: .verb,
                surfaceForm: "lief",
                pageIndex: 4,
                bounds: StoredPDFWordRect(CGRect(x: 80, y: 20, width: 30, height: 12)),
                textAnchor: sharedThirdAnchor,
                context: "lief lief lief",
                question: "What is lief?",
                answer: "ran",
                createdAt: Date(timeIntervalSince1970: 60),
                srs: srs
            )
            assert(
                sharedStore.upsertPDFRecord(documentID: sharedOwnerDocumentID, record: resolvedNewOccurrence),
                "a genuinely new resolved occurrence should save"
            )
            let withResolvedOwner = sharedStore.loadPDFRecords(documentID: sharedOwnerDocumentID)
            let newOwnerID = withResolvedOwner.first { $0.id == "resolved-new-occurrence" }?.vocabularyID
            assert(newOwnerID != nil && newOwnerID != legacyOwnerID, "new resolved occurrences must not be absorbed into a legacy wildcard owner")
            assert(Set(withResolvedOwner.filter { $0.id != "resolved-new-occurrence" }.compactMap(\.vocabularyID)) == [legacyOwnerID], "legacy owner membership must remain unchanged")

            let snapshot = withResolvedOwner
            assert(
                sharedStore.savePDFRecords(documentID: sharedOwnerDocumentID, records: Array(snapshot.reversed())),
                "full save should preserve ownership with reversed input order"
            )
            assert(
                sharedStore.savePDFRecords(documentID: sharedOwnerDocumentID, records: snapshot),
                "full save should preserve ownership with original input order"
            )
        }
        do {
            let reopened = WordRecordSQLiteStore(databaseURL: sharedOwnerURL)
            let reopenedRecords = reopened.loadPDFRecords(documentID: sharedOwnerDocumentID)
            let reopenedLegacy = reopenedRecords.filter { $0.id != "resolved-new-occurrence" }
            assert(reopenedLegacy.count == 2, "reopen should preserve both legacy occurrences")
            assert(Set(reopenedLegacy.compactMap(\.vocabularyID)).count == 1, "reopen should preserve the shared legacy learning owner")
            assert(reopenedLegacy.first { $0.id == "legacy-occurrence-a" }?.lexicalKey == "de|laufen|verb|", "reopen should preserve additive occurrence evidence")
            assert(reopenedLegacy.first { $0.id == "legacy-occurrence-b" }?.lexicalKey == nil, "reopen should preserve the unresolved sibling")
            assert(reopenedLegacy.allSatisfy { $0.answer == "ran" }, "reopen should preserve the restored shared answer")
            assert(reopenedLegacy.allSatisfy { $0.srs?.reviewCount == 2 }, "reopen should preserve restored shared SRS history")
        }

        let ambiguousURL = dbDirectory.appendingPathComponent("ambiguous-source.sqlite3")
        do {
            let ambiguousStore = WordRecordSQLiteStore(databaseURL: ambiguousURL)
            let ambiguousDocumentID = "ambiguous-source-doc"
            let ambiguousFirst = pdfRecord(id: "ambiguous-a", word: "alpha", answer: "one", createdAt: 1)
            let ambiguousSecond = pdfRecord(
                id: "ambiguous-b",
                word: "beta",
                answer: "two",
                createdAt: 2,
                bounds: CGRect(x: 100, y: 200, width: 30, height: 12)
            )
            assert(
                ambiguousStore.savePDFRecords(documentID: ambiguousDocumentID, records: [ambiguousFirst, ambiguousSecond]),
                "ambiguous-source fixture should save"
            )
            forcePDFOccurrenceLocationKey(
                at: ambiguousURL,
                documentID: ambiguousDocumentID,
                occurrenceID: ambiguousSecond.id,
                locationKey: ambiguousFirst.occurrenceKey
            )
            let ambiguousRetry = pdfRecord(
                id: "ambiguous-retry",
                word: "gamma",
                answer: "three",
                createdAt: 3,
                bounds: ambiguousFirst.bounds.cgRect
            )
            assert(
                !ambiguousStore.upsertPDFRecord(documentID: ambiguousDocumentID, record: ambiguousRetry),
                "ambiguous stable-source matching must fail closed"
            )
            let afterAmbiguousRetry = ambiguousStore.loadPDFRecords(documentID: ambiguousDocumentID)
            assert(afterAmbiguousRetry.count == 2, "ambiguous retry must not write a duplicate occurrence")
            assert(!afterAmbiguousRetry.contains { $0.id == "ambiguous-retry" }, "ambiguous retry must leave the original rows unchanged")
        }
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
            assert(migrated.allSatisfy { $0.language == nil }, "legacy PDF rows without language metadata should remain unresolved")
        }

        let legacyWebDBURL = dbDirectory.appendingPathComponent("legacy-web-word-records.sqlite3")
        createLegacyWebDatabase(at: legacyWebDBURL)
        do {
            let legacyStore = WordRecordSQLiteStore(databaseURL: legacyWebDBURL)
            let legacy = legacyStore.loadWebRecords(documentID: "legacy-web-doc")
            assert(legacy.count == 1, "additive web migration should preserve legacy rows")
            assert(legacy.first?.occurrenceSurfaceForm == "ging", "legacy web rows should fall back to their saved word as surface")
            assert(legacy.first?.language == nil, "legacy web rows without language metadata should remain unresolved")

            var repaired = legacy[0]
            repaired.vocabularyID = "legacy-go"
            repaired.language = .german
            repaired.lemma = "gehen"
            repaired.surfaceForm = "ging"
            assert(legacyStore.upsertWebRecord(documentID: "legacy-web-doc", record: repaired), "migrated web columns should accept parity metadata")
        }
        do {
            let reopened = WordRecordSQLiteStore(databaseURL: legacyWebDBURL)
            let repaired = reopened.loadWebRecords(documentID: "legacy-web-doc").first
            assert(repaired?.vocabularyID == "legacy-go", "migrated web vocabulary identity should persist after reopen")
            assert(repaired?.language == .german, "migrated web language identity should persist after reopen")
            assert(repaired?.lemma == "gehen", "migrated web lemma should persist after reopen")
            assert(repaired?.surfaceForm == "ging", "migrated web surface should persist after reopen")
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

            let flexionStore = GermanFlexionStore(store: store)
            var contextualCalls = 0
            let weak = GermanFormLabeler.persistentCachedLabel(
                surfaceForm: "gegangen",
                lemma: "gehen",
                context: "gegangen",
                labelStore: store,
                flexionStore: flexionStore,
                offlineResolver: { _, _, _ in
                    contextualCalls += 1
                    return .contextual(nil)
                }
            )
            assert(weak == nil, "weak context may remain unlabeled")
            assert(
                store.germanFormLabel(
                    surfaceKey: "gegangen",
                    lemmaKey: "gehen",
                    version: GermanFormLabeler.labelingVersion
                ) == nil,
                "a contextual nil must not become a global cache hit"
            )
            let strong = GermanFormLabeler.persistentCachedLabel(
                surfaceForm: "gegangen",
                lemma: "gehen",
                context: "Er ist nach Hause gegangen.",
                labelStore: store,
                flexionStore: flexionStore,
                offlineResolver: { _, _, _ in
                    contextualCalls += 1
                    return .contextual(.partizipII)
                }
            )
            assert(strong == .partizipII, "later strong context should reach the labeler")
            assert(contextualCalls == 2, "distinct contextual verdicts should both be evaluated")

            var deterministicCalls = 0
            let deterministic = GermanFormLabeler.persistentCachedLabel(
                surfaceForm: "Bücher",
                lemma: "Buch",
                context: "Die Bücher liegen dort.",
                labelStore: store,
                flexionStore: flexionStore,
                offlineResolver: { _, _, _ in
                    deterministicCalls += 1
                    return .contextIndependent(.plural)
                }
            )
            assert(deterministic == .plural, "context-independent morphology should produce a label")
            let deterministicHit = GermanFormLabeler.persistentCachedLabel(
                surfaceForm: "Bücher",
                lemma: "Buch",
                context: "Bücher",
                labelStore: store,
                flexionStore: flexionStore,
                offlineResolver: { _, _, _ in
                    deterministicCalls += 1
                    return .contextual(nil)
                }
            )
            assert(deterministicHit == .plural, "a deterministic label should be reusable across contexts")
            assert(deterministicCalls == 1, "a deterministic cache hit should skip recomputation")
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
            var sameSpot = pdfRecord(
                id: "infl",
                word: "Häuser",
                answer: "houses",
                createdAt: 50,
                bounds: CGRect(x: 50, y: 60, width: 30, height: 12)
            )
            sameSpot.lemma = "Häuser"
            _ = store.savePDFRecords(documentID: "doc", records: [base, sameSpot])
            forcePDFOccurrenceLocationKey(
                at: url,
                documentID: "doc",
                occurrenceID: sameSpot.id,
                locationKey: base.occurrenceKey
            )
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

private func forcePDFOccurrenceLocationKey(
    at url: URL,
    documentID: String,
    occurrenceID: String,
    locationKey: String
) {
    var db: OpaquePointer?
    assert(sqlite3_open(url.path, &db) == SQLITE_OK, "ambiguous-source fixture should open")
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    let sql = "UPDATE pdf_vocabulary_occurrences SET location_key = ? WHERE document_id = ? AND id = ?"
    assert(sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, "ambiguous-source fixture update should prepare")
    defer { sqlite3_finalize(statement) }
    sqlite3_bind_text(statement, 1, (locationKey as NSString).utf8String, -1, nil)
    sqlite3_bind_text(statement, 2, (documentID as NSString).utf8String, -1, nil)
    sqlite3_bind_text(statement, 3, (occurrenceID as NSString).utf8String, -1, nil)
    assert(sqlite3_step(statement) == SQLITE_DONE, "ambiguous-source fixture should create two owners for one location")
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

private func createLegacyWebDatabase(at url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var db: OpaquePointer?
    assert(sqlite3_open(url.path, &db) == SQLITE_OK, "legacy web migration fixture should open")
    defer { sqlite3_close(db) }
    let sql = """
    CREATE TABLE web_word_records (
        document_id TEXT NOT NULL, id TEXT NOT NULL, word TEXT NOT NULL,
        context TEXT NOT NULL, occurrence_index INTEGER, scroll_progress REAL NOT NULL,
        question TEXT NOT NULL, answer TEXT NOT NULL, dictionary_tags TEXT,
        dictionary_frequency INTEGER, created_at REAL NOT NULL, srs_json TEXT,
        PRIMARY KEY(document_id, id)
    );
    INSERT INTO web_word_records VALUES
      ('legacy-web-doc','legacy-web-a','ging','Er ging nach Hause.',7,0.42,'','went',NULL,NULL,1,NULL);
    """
    assert(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, "legacy web migration fixture should be created")
}
