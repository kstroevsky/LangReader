import Foundation
import SQLite3
import XCTest
import LeafReaderCore
@testable import LeafReaderApp

final class VocabularyPreparationPersistenceXCTests: XCTestCase {
    func testDocumentLanguageMetadataRestoresManualChoiceAsAuthoritative() throws {
        let suite = "VocabularyDocumentLanguagePersistenceXCTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = VocabularyDocumentLanguageStore(documentID: "document-a", defaults: defaults)
        let manual = VocabularyLanguageResolution.resolved(VocabularyResolvedLanguage(
            id: .german,
            provenance: .userSelected
        ))

        XCTAssertTrue(store.save(resolution: manual))
        XCTAssertEqual(store.load()?.restoredResolution, manual)
    }

    func testDocumentLanguageMetadataMarksAutomaticRestoreAsPersistedEvidence() throws {
        let suite = "VocabularyDocumentLanguageAutomaticXCTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = VocabularyDocumentLanguageStore(documentID: "document-a", defaults: defaults)
        let evidence = VocabularyLanguageEvidence(
            provider: VocabularyProviderDescriptor(
                id: "language.test",
                version: "1",
                supportedLanguageRanges: []
            ),
            sampledCharacterCount: 400,
            sampledUnitCount: 2
        )
        let automatic = VocabularyLanguageResolution.resolved(VocabularyResolvedLanguage(
            id: .english,
            provenance: .automaticDetection,
            evidence: evidence
        ))

        XCTAssertTrue(store.save(resolution: automatic))
        let restored = try XCTUnwrap(store.load()?.restoredResolution?.resolvedLanguage)
        XCTAssertEqual(restored.id, .english)
        XCTAssertEqual(restored.provenance, .persistedDocumentMetadata)
        XCTAssertEqual(restored.evidence, evidence)
    }

    func testManualLanguageResolutionRejectsLaterAutomaticOverwrite() {
        var state = ReaderVocabularyState()
        let manual = VocabularyLanguageResolution.resolved(VocabularyResolvedLanguage(
            id: .german,
            provenance: .userSelected
        ))
        let automatic = VocabularyLanguageResolution.resolved(VocabularyResolvedLanguage(
            id: .english,
            provenance: .automaticDetection
        ))

        XCTAssertTrue(state.updateLanguageResolution(manual))
        let revision = state.languageRevision
        XCTAssertFalse(state.updateLanguageResolution(automatic))
        XCTAssertEqual(state.documentLanguageResolution, manual)
        XCTAssertEqual(state.languageRevision, revision)

        let changedManual = VocabularyLanguageResolution.resolved(VocabularyResolvedLanguage(
            id: .english,
            provenance: .userSelected
        ))
        XCTAssertTrue(state.updateLanguageResolution(changedManual))
        XCTAssertEqual(state.documentLanguageResolution, changedManual)
        XCTAssertGreaterThan(state.languageRevision, revision)
    }

    func testDocumentScopedSessionRoundTripAndClear() throws {
        let suite = "VocabularyPreparationPersistenceXCTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = VocabularyPreparationSessionStore(documentID: "document-a", defaults: defaults)
        let session = VocabularyPreparationSession(
            mode: .targetCoverage(0.98),
            invitationState: .started,
            answers: [
                VocabularyAssessmentAnswer(
                    canonicalKey: "develop",
                    evidence: .legacyKnown,
                    questionOrdinal: 1,
                    selectionType: .initialCalibration,
                    predictedKnownBeforeAnswer: 0.72
                ),
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

    func testLegacySessionPayloadIsArchivedBeforeIncompatibleReplacementAndSurvivesReopen() throws {
        let suite = "VocabularyPreparationLegacyArchiveXCTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let documentID = "document-legacy"
        let key = "bookSession.\(documentID).vocabularyPreparation"
        let legacy = VocabularyPreparationSession(
            invitationState: .started,
            answers: [VocabularyAssessmentAnswer(canonicalKey: "legacy", evidence: .legacyKnown)],
            finalSelection: ["legacy"],
            algorithmVersion: 6,
            readerPriorContributionRecorded: true,
            readerPriorContributionID: "legacy-contribution"
        )
        let legacyPayload = try JSONEncoder().encode(legacy)
        defaults.set(legacyPayload, forKey: key)
        let store = VocabularyPreparationSessionStore(documentID: documentID, defaults: defaults)

        var invitationUpdate = try XCTUnwrap(store.load())
        invitationUpdate.invitationState = .dismissed
        XCTAssertTrue(store.save(invitationUpdate))

        let fresh = VocabularyPreparationSession(
            invitationState: .dismissed,
            compatibilityFingerprint: fingerprint(language: .english),
            documentIdentity: documentID,
            textIdentity: "text-v2",
            candidateInventoryIdentity: "inventory-v2"
        )
        XCTAssertTrue(store.archiveAndReplace(
            with: fresh,
            reason: "incompatible-preparation-semantics",
            archivedAt: Date(timeIntervalSince1970: 123)
        ))

        let reopened = VocabularyPreparationSessionStore(documentID: documentID, defaults: defaults)
        XCTAssertEqual(reopened.load(), fresh)
        let archived = try XCTUnwrap(reopened.archivedSessions().only)
        XCTAssertEqual(archived.archivedAt, Date(timeIntervalSince1970: 123))
        XCTAssertEqual(archived.reason, "incompatible-preparation-semantics")
        XCTAssertEqual(archived.session, legacy)
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

    private func fingerprint(language: VocabularyLanguageID) -> VocabularyPreparationCompatibilityFingerprint {
        VocabularyPreparationCompatibilityFingerprint(
            algorithmVersion: VocabularyPreparationSession.currentAlgorithmVersion,
            language: language,
            languageProfileVersion: "test-profile-v1",
            linguisticProviders: [VocabularyLinguisticCacheIdentity.builtInProvider],
            linguisticRuntimeSignature: "test-runtime",
            difficultyProvider: VocabularyDifficultyProviderSemanticIdentity(
                providerID: "difficulty.test",
                providerVersion: "1"
            ),
            definitionProvider: VocabularySemanticProviderIdentity(
                id: "definition.test",
                version: "1",
                normalizationVersion: VocabularyNormalizationPolicy.currentVersion
            )
        )
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
