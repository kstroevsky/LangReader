import Foundation
import SQLite3
import LeafReaderCore

/// SQLite access is serialized by `lock`; the handle and lazy row mappers are
/// never used outside that critical section after initialization.
final class WordRecordSQLiteStore: @unchecked Sendable {
    static let shared = WordRecordSQLiteStore(databaseURL: defaultDatabaseURL())

    private let lock = NSLock()
    private var db: OpaquePointer?
    private let codec = WordRecordSQLiteJSONCodec()
    private lazy var pdfMapper = PDFWordRecordSQLiteMapper(codec: codec)
    private lazy var pdfVocabularyMapper = PDFVocabularySQLiteMapper(codec: codec)
    private lazy var webMapper = WebWordRecordSQLiteMapper(codec: codec)

    init(databaseURL: URL?) {
        guard let url = databaseURL else {
            NSLog("LeafReader word records: no database URL available")
            return
        }
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            NSLog("LeafReader word records: failed to create database directory at %@ (error=%@)", directory.path, error.localizedDescription)
            return
        }
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            NSLog("LeafReader word records: failed to open database at %@ (error=%@)", url.path, message)
            sqlite3_close(db)
            db = nil
            return
        }
        createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    func loadPDFRecords(documentID: String) -> [StoredPDFWordRecord] {
        locked {
            loadRecords(
                sql: PDFVocabularySQLiteMapper.selectSQL,
                prepareOperation: "prepare load PDF records",
                bind: { bindText(documentID, at: .documentID, statement: $0) },
                decode: pdfVocabularyMapper.decode
            )
        }
    }

    @discardableResult
    func savePDFRecords(documentID: String, records: [StoredPDFWordRecord]) -> Bool {
        locked {
            guard beginTransaction() else { return false }
            guard execute(
                sql: "DELETE FROM pdf_vocabulary_words WHERE document_id = ?",
                bindings: [documentID],
                operation: "delete existing PDF vocabulary"
            ) else {
                rollbackTransaction()
                return false
            }

            var didFail = false
            for record in records {
                guard insertNormalizedPDFRecord(documentID: documentID, record: record) else {
                    didFail = true
                    break
                }
            }
            if didFail {
                rollbackTransaction()
                return false
            }
            guard deleteOrphanedPDFVocabularyWords(documentID: documentID) else {
                rollbackTransaction()
                return false
            }
            guard commitTransaction() else {
                rollbackTransaction()
                return false
            }
            return true
        }
    }

    @discardableResult
    func upsertPDFRecord(documentID: String, record: StoredPDFWordRecord) -> Bool {
        locked {
            guard beginTransaction() else { return false }
            guard insertNormalizedPDFRecord(documentID: documentID, record: record) else {
                rollbackTransaction()
                return false
            }
            guard deleteOrphanedPDFVocabularyWords(documentID: documentID) else {
                rollbackTransaction()
                return false
            }
            guard commitTransaction() else {
                rollbackTransaction()
                return false
            }
            return true
        }
    }

    @discardableResult
    func upsertPDFRecords(documentID: String, records: [StoredPDFWordRecord]) -> Bool {
        guard !records.isEmpty else { return true }
        return locked {
            guard beginTransaction() else { return false }
            for record in records {
                guard insertNormalizedPDFRecord(documentID: documentID, record: record) else {
                    rollbackTransaction()
                    return false
                }
            }
            guard deleteOrphanedPDFVocabularyWords(documentID: documentID) else {
                rollbackTransaction()
                return false
            }
            guard commitTransaction() else {
                rollbackTransaction()
                return false
            }
            return true
        }
    }

    @discardableResult
    func deletePDFRecords(documentID: String, ids: [String]) -> Bool {
        locked {
            guard deleteRecords(table: "pdf_vocabulary_occurrences", documentID: documentID, ids: ids) else {
                return false
            }
            return execute(
                sql: "DELETE FROM pdf_vocabulary_words WHERE document_id = ? AND id NOT IN (SELECT vocabulary_id FROM pdf_vocabulary_occurrences WHERE document_id = ?)",
                bindings: [documentID, documentID],
                operation: "delete orphaned PDF vocabulary words"
            )
        }
    }

    func loadWebRecords(documentID: String) -> [StoredWebWordRecord] {
        locked {
            loadRecords(
                sql: WebWordRecordSQLiteMapper.selectSQL,
                prepareOperation: "prepare load web records",
                bind: { bindText(documentID, at: .documentID, statement: $0) },
                decode: webMapper.decode
            )
        }
    }

    @discardableResult
    func saveWebRecords(documentID: String, records: [StoredWebWordRecord]) -> Bool {
        locked {
            guard beginTransaction() else { return false }
            guard execute(
                sql: "DELETE FROM web_word_records WHERE document_id = ?",
                bindings: [documentID],
                operation: "delete existing web records"
            ) else {
                rollbackTransaction()
                return false
            }

            var didFail = false
            for record in records {
                guard insertWebRecord(documentID: documentID, record: record, prepareOperation: "prepare save web record", stepOperation: "insert web record") else {
                    didFail = true
                    break
                }
            }
            if didFail {
                rollbackTransaction()
                return false
            }
            guard commitTransaction() else {
                rollbackTransaction()
                return false
            }
            return true
        }
    }

    @discardableResult
    func upsertWebRecord(documentID: String, record: StoredWebWordRecord) -> Bool {
        upsertWebRecords(documentID: documentID, records: [record])
    }

    /// A vocabulary group may have several web occurrences.  It is persisted
    /// as one logical change so a failed write cannot leave half the group with
    /// an old answer and half with a new one.
    @discardableResult
    func upsertWebRecords(documentID: String, records: [StoredWebWordRecord]) -> Bool {
        guard !records.isEmpty else { return true }
        return locked {
            guard beginTransaction() else { return false }
            for record in records {
                guard insertWebRecord(documentID: documentID, record: record) else {
                    rollbackTransaction()
                    return false
                }
            }
            guard commitTransaction() else {
                rollbackTransaction()
                return false
            }
            return true
        }
    }

    @discardableResult
    func deleteWebRecords(documentID: String, ids: [String]) -> Bool {
        locked {
            deleteRecords(table: "web_word_records", documentID: documentID, ids: ids)
        }
    }

    // MARK: - German flexion cache

    /// Replaces the cached flexion table for one lemma.
    ///
    /// An entry with no forms is still written: it records that the lemma was
    /// looked up and has no table, so the same page is not refetched on every
    /// subsequent encounter.
    @discardableResult
    func saveGermanFlexion(_ entry: StoredGermanFlexion) -> Bool {
        locked {
            guard beginTransaction() else { return false }
            guard execute(
                sql: "DELETE FROM german_flexion_lemmas WHERE lemma_key = ?",
                bindings: [entry.lemmaKey],
                operation: "delete german flexion lemma"
            ) else {
                rollbackTransaction()
                return false
            }
            // The persistent label cache stores only the flexion-independent
            // offline label; flexion refinement is composed fresh on read (see
            // GermanFormLabeler.persistentCachedLabel), so a new paradigm needs no
            // label-cache invalidation here.
            let insertedLemma = executeStatement(
                sql: """
                INSERT INTO german_flexion_lemmas (lemma_key, lemma, genus, auxiliary, fetched_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                prepareOperation: "prepare insert german flexion lemma",
                stepOperation: "insert german flexion lemma"
            ) { statement in
                bindSQLiteText(entry.lemmaKey, index: 1, statement: statement)
                bindSQLiteText(entry.lemma, index: 2, statement: statement)
                bindSQLiteOptionalText(entry.genus, index: 3, statement: statement)
                bindSQLiteOptionalText(entry.auxiliary, index: 4, statement: statement)
                sqlite3_bind_double(statement, 5, entry.fetchedAt.timeIntervalSince1970)
            }
            guard insertedLemma else {
                rollbackTransaction()
                return false
            }

            for form in entry.forms {
                let surfaceKey = VocabularyTextPolicy.canonicalVocabularyKey(form.surface)
                guard !surfaceKey.isEmpty else { continue }
                let inserted = executeStatement(
                    sql: """
                    INSERT OR REPLACE INTO german_flexion_forms
                        (lemma_key, parameter, surface, surface_key, is_variant)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    prepareOperation: "prepare insert german flexion form",
                    stepOperation: "insert german flexion form"
                ) { statement in
                    bindSQLiteText(entry.lemmaKey, index: 1, statement: statement)
                    bindSQLiteText(form.parameter, index: 2, statement: statement)
                    bindSQLiteText(form.surface, index: 3, statement: statement)
                    bindSQLiteText(surfaceKey, index: 4, statement: statement)
                    sqlite3_bind_int(statement, 5, form.isVariant ? 1 : 0)
                }
                guard inserted else {
                    rollbackTransaction()
                    return false
                }
            }
            guard commitTransaction() else {
                rollbackTransaction()
                return false
            }
            return true
        }
    }

    /// Whether this lemma has already been fetched, including when the fetch
    /// found no table. Used to avoid repeat network lookups.
    func hasGermanFlexion(lemmaKey: String) -> Bool {
        locked {
            !loadRecords(
                sql: "SELECT lemma_key FROM german_flexion_lemmas WHERE lemma_key = ? LIMIT 1",
                prepareOperation: "prepare german flexion existence check",
                bind: { bindSQLiteText(lemmaKey, index: 1, statement: $0) },
                decode: { stringColumn($0, 0) }
            ).isEmpty
        }
    }

    /// Every cached parameter naming this surface form, across all lemmas.
    ///
    /// The reverse direction is what repairs grouping: `Häuser` resolves to
    /// `Haus` here even though the offline lemmatizer leaves it unchanged.
    func germanFlexionMatches(surfaceForm: String) -> [StoredGermanFlexionMatch] {
        let surfaceKey = VocabularyTextPolicy.canonicalVocabularyKey(surfaceForm)
        guard !surfaceKey.isEmpty else { return [] }
        return locked {
            loadRecords(
                sql: """
                SELECT l.lemma, f.parameter, f.surface, f.is_variant
                FROM german_flexion_forms f
                JOIN german_flexion_lemmas l ON l.lemma_key = f.lemma_key
                WHERE f.surface_key = ?
                """,
                prepareOperation: "prepare german flexion reverse lookup",
                bind: { bindSQLiteText(surfaceKey, index: 1, statement: $0) },
                decode: { statement in
                    guard let lemma = stringColumn(statement, 0),
                          let parameter = stringColumn(statement, 1),
                          let surface = stringColumn(statement, 2) else {
                        return nil
                    }
                    return StoredGermanFlexionMatch(
                        lemma: lemma,
                        parameter: parameter,
                        surface: surface,
                        isVariant: sqlite3_column_int(statement, 3) != 0
                    )
                }
            )
        }
    }

    // MARK: - German form-label cache

    /// One cached grammatical label. `label` is nil when the labeler ran and
    /// found none — distinct from a lookup miss, which returns nil for the whole
    /// `CachedFormLabel?`, so a form proven to have no label is not recomputed.
    struct CachedFormLabel: Equatable {
        let label: String?
    }

    /// The cached label for a `(surface, lemma)` pair computed by the given
    /// labeler version, or nil when the pair has never been labeled (or was
    /// labeled by a different version and must be recomputed).
    func germanFormLabel(surfaceKey: String, lemmaKey: String, version: Int) -> CachedFormLabel? {
        guard !surfaceKey.isEmpty, !lemmaKey.isEmpty else { return nil }
        return locked {
            loadRecords(
                sql: """
                SELECT label FROM german_form_labels
                WHERE surface_key = ? AND lemma_key = ? AND labeler_version = ?
                LIMIT 1
                """,
                prepareOperation: "prepare german form label lookup",
                bind: { statement in
                    bindSQLiteText(surfaceKey, index: 1, statement: statement)
                    bindSQLiteText(lemmaKey, index: 2, statement: statement)
                    sqlite3_bind_int(statement, 3, Int32(version))
                },
                decode: { statement -> CachedFormLabel in
                    let raw = stringColumn(statement, 0) ?? ""
                    return CachedFormLabel(label: raw.isEmpty ? nil : raw)
                }
            ).first
        }
    }

    /// Persists the labeler's verdict for a `(surface, lemma)` pair. An empty
    /// string records "no label" so a proven-unlabelable form is not recomputed.
    @discardableResult
    func saveGermanFormLabel(surfaceKey: String, lemmaKey: String, label: String?, version: Int) -> Bool {
        guard !surfaceKey.isEmpty, !lemmaKey.isEmpty else { return false }
        return locked {
            executeStatement(
                sql: """
                INSERT OR REPLACE INTO german_form_labels
                    (surface_key, lemma_key, label, labeler_version, created_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                prepareOperation: "prepare insert german form label",
                stepOperation: "insert german form label"
            ) { statement in
                bindSQLiteText(surfaceKey, index: 1, statement: statement)
                bindSQLiteText(lemmaKey, index: 2, statement: statement)
                bindSQLiteText(label ?? "", index: 3, statement: statement)
                sqlite3_bind_int(statement, 4, Int32(version))
                sqlite3_bind_double(statement, 5, Date().timeIntervalSince1970)
            }
        }
    }

    /// Drops cached labels for a lemma so they are recomputed. Called when the
    /// flexion table for that lemma changes, since a paradigm refines
    /// `finiteVerb` into Präsens/Präteritum and a bare plural into a cased form.
    @discardableResult
    func deleteGermanFormLabels(lemmaKey: String) -> Bool {
        guard !lemmaKey.isEmpty else { return false }
        return locked {
            execute(
                sql: "DELETE FROM german_form_labels WHERE lemma_key = ?",
                bindings: [lemmaKey],
                operation: "delete german form labels for lemma"
            )
        }
    }

    /// Re-files vocabulary saved under an inflected spelling onto its lemma.
    ///
    /// `canonical_key` carries `UNIQUE(document_id, canonical_key)`, so a word
    /// saved as `Häuser` before its paradigm was known cannot simply be
    /// re-keyed when a record for `Haus` already exists — the two have to be
    /// merged. Both paths run inside one transaction and are idempotent:
    /// re-running finds no source rows and does nothing.
    ///
    /// Only `pdf_vocabulary_words` is affected. Web records are keyed by their
    /// literal text and have no lemma column to reconcile.
    @discardableResult
    func regroupVocabulary(fromKey: String, intoKey: String, lemma: String) -> Int {
        guard !fromKey.isEmpty, !intoKey.isEmpty, fromKey != intoKey else { return 0 }

        struct SourceRow {
            let documentID: String
            let id: String
            let answer: String
            let createdAt: Double
        }

        return locked {
            let sources = loadRecords(
                sql: """
                SELECT document_id, id, answer, created_at
                FROM pdf_vocabulary_words WHERE canonical_key = ?
                """,
                prepareOperation: "prepare vocabulary regroup lookup",
                bind: { bindSQLiteText(fromKey, index: 1, statement: $0) },
                decode: { statement -> SourceRow? in
                    guard let documentID = stringColumn(statement, 0),
                          let id = stringColumn(statement, 1) else { return nil }
                    return SourceRow(
                        documentID: documentID,
                        id: id,
                        answer: stringColumn(statement, 2) ?? "",
                        createdAt: sqlite3_column_double(statement, 3)
                    )
                }
            )
            guard !sources.isEmpty, beginTransaction() else { return 0 }

            var regrouped = 0
            for source in sources {
                let existing = loadRecords(
                    sql: """
                    SELECT id FROM pdf_vocabulary_words
                    WHERE document_id = ? AND canonical_key = ?
                    """,
                    prepareOperation: "prepare vocabulary regroup target lookup",
                    bind: { statement in
                        bindSQLiteText(source.documentID, index: 1, statement: statement)
                        bindSQLiteText(intoKey, index: 2, statement: statement)
                    },
                    decode: { stringColumn($0, 0) }
                )

                guard let targetID = existing.first else {
                    // No record under the lemma yet: re-key in place.
                    guard execute(
                        sql: """
                        UPDATE pdf_vocabulary_words SET canonical_key = ?, lemma = ?
                        WHERE document_id = ? AND id = ?
                        """,
                        bindings: [intoKey, lemma, source.documentID, source.id],
                        operation: "rekey vocabulary to lemma"
                    ) else {
                        rollbackTransaction()
                        return 0
                    }
                    regrouped += 1
                    continue
                }

                // A record already exists under the lemma: move the occurrences
                // across. OR IGNORE drops any occurrence whose location is
                // already recorded on the target — a genuine duplicate, not a
                // loss — and the cascade below removes the skipped rows.
                guard execute(
                    sql: """
                    UPDATE OR IGNORE pdf_vocabulary_occurrences SET vocabulary_id = ?
                    WHERE document_id = ? AND vocabulary_id = ?
                    """,
                    bindings: [targetID, source.documentID, source.id],
                    operation: "move occurrences to lemma record"
                ) else {
                    rollbackTransaction()
                    return 0
                }

                // Keep the surviving record's answer if it has one, otherwise
                // adopt the source's, and keep the earlier creation date so the
                // entry does not appear newer than it is.
                let merged = executeStatement(
                    sql: """
                    UPDATE pdf_vocabulary_words
                    SET answer = CASE WHEN answer IS NULL OR answer = '' THEN ? ELSE answer END,
                        created_at = min(created_at, ?),
                        lemma = ?
                    WHERE document_id = ? AND id = ?
                    """,
                    prepareOperation: "prepare merge vocabulary into lemma",
                    stepOperation: "merge vocabulary into lemma"
                ) { statement in
                    bindSQLiteText(source.answer, index: 1, statement: statement)
                    sqlite3_bind_double(statement, 2, source.createdAt)
                    bindSQLiteText(lemma, index: 3, statement: statement)
                    bindSQLiteText(source.documentID, index: 4, statement: statement)
                    bindSQLiteText(targetID, index: 5, statement: statement)
                }
                guard merged else {
                    rollbackTransaction()
                    return 0
                }

                guard execute(
                    sql: "DELETE FROM pdf_vocabulary_words WHERE document_id = ? AND id = ?",
                    bindings: [source.documentID, source.id],
                    operation: "delete merged vocabulary row"
                ) else {
                    rollbackTransaction()
                    return 0
                }
                regrouped += 1
            }

            guard commitTransaction() else {
                rollbackTransaction()
                return 0
            }
            return regrouped
        }
    }

    private func createTables() {
        let sql = """
        PRAGMA foreign_keys = ON;
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS pdf_word_records (
            document_id TEXT NOT NULL,
            id TEXT NOT NULL,
            word TEXT NOT NULL,
            page_index INTEGER NOT NULL,
            bounds_json TEXT NOT NULL,
            context TEXT,
            question TEXT NOT NULL,
            answer TEXT NOT NULL,
            dictionary_tags TEXT,
            dictionary_frequency INTEGER,
            created_at REAL NOT NULL,
            srs_json TEXT,
            PRIMARY KEY(document_id, id)
        );
        CREATE INDEX IF NOT EXISTS idx_pdf_word_records_document ON pdf_word_records(document_id);
        CREATE INDEX IF NOT EXISTS idx_pdf_word_records_word ON pdf_word_records(document_id, word);
        CREATE TABLE IF NOT EXISTS pdf_vocabulary_words (
            document_id TEXT NOT NULL,
            id TEXT NOT NULL,
            canonical_key TEXT NOT NULL,
            word TEXT NOT NULL,
            lemma TEXT,
            question TEXT NOT NULL,
            answer TEXT NOT NULL,
            dictionary_tags TEXT,
            dictionary_frequency INTEGER,
            created_at REAL NOT NULL,
            srs_json TEXT,
            PRIMARY KEY(document_id, id),
            UNIQUE(document_id, canonical_key)
        );
        CREATE INDEX IF NOT EXISTS idx_pdf_vocabulary_words_document ON pdf_vocabulary_words(document_id);
        CREATE TABLE IF NOT EXISTS pdf_vocabulary_occurrences (
            document_id TEXT NOT NULL,
            id TEXT NOT NULL,
            vocabulary_id TEXT NOT NULL,
            location_key TEXT NOT NULL,
            page_index INTEGER NOT NULL,
            bounds_json TEXT NOT NULL,
            text_anchor_json TEXT,
            context TEXT,
            surface_form TEXT,
            created_at REAL NOT NULL,
            PRIMARY KEY(document_id, id),
            UNIQUE(document_id, vocabulary_id, location_key),
            FOREIGN KEY(document_id, vocabulary_id)
                REFERENCES pdf_vocabulary_words(document_id, id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_pdf_vocabulary_occurrences_word
            ON pdf_vocabulary_occurrences(document_id, vocabulary_id);
        CREATE TABLE IF NOT EXISTS word_record_schema_metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS web_word_records (
            document_id TEXT NOT NULL,
            id TEXT NOT NULL,
            vocabulary_id TEXT,
            word TEXT NOT NULL,
            lemma TEXT,
            surface_form TEXT,
            context TEXT NOT NULL,
            occurrence_index INTEGER,
            scroll_progress REAL NOT NULL,
            question TEXT NOT NULL,
            answer TEXT NOT NULL,
            dictionary_tags TEXT,
            dictionary_frequency INTEGER,
            created_at REAL NOT NULL,
            srs_json TEXT,
            PRIMARY KEY(document_id, id)
        );
        CREATE INDEX IF NOT EXISTS idx_web_word_records_document ON web_word_records(document_id);
        CREATE INDEX IF NOT EXISTS idx_web_word_records_word ON web_word_records(document_id, word);
        CREATE TABLE IF NOT EXISTS german_flexion_lemmas (
            lemma_key TEXT PRIMARY KEY,
            lemma TEXT NOT NULL,
            genus TEXT,
            auxiliary TEXT,
            fetched_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS german_flexion_forms (
            lemma_key TEXT NOT NULL,
            parameter TEXT NOT NULL,
            surface TEXT NOT NULL,
            surface_key TEXT NOT NULL,
            is_variant INTEGER NOT NULL,
            PRIMARY KEY(lemma_key, parameter, surface_key),
            FOREIGN KEY(lemma_key) REFERENCES german_flexion_lemmas(lemma_key) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_german_flexion_surface
            ON german_flexion_forms(surface_key);
        CREATE TABLE IF NOT EXISTS german_form_labels (
            surface_key TEXT NOT NULL,
            lemma_key TEXT NOT NULL,
            label TEXT NOT NULL,
            labeler_version INTEGER NOT NULL,
            created_at REAL NOT NULL,
            PRIMARY KEY(surface_key, lemma_key)
        );
        CREATE INDEX IF NOT EXISTS idx_german_form_labels_lemma
            ON german_form_labels(lemma_key);
        """
        executeRaw(sql, operation: "create word record tables")
        migrateColumns()
        migrateLegacyPDFRecordsIfNeeded()
    }

    private func migrateColumns() {
        ensureColumn(table: "web_word_records", name: "occurrence_index", definition: "INTEGER")
        ensureColumn(table: "web_word_records", name: "vocabulary_id", definition: "TEXT")
        ensureColumn(table: "web_word_records", name: "lemma", definition: "TEXT")
        ensureColumn(table: "web_word_records", name: "surface_form", definition: "TEXT")
        ensureColumn(table: "pdf_word_records", name: "dictionary_tags", definition: "TEXT")
        ensureColumn(table: "web_word_records", name: "dictionary_tags", definition: "TEXT")
        ensureColumn(table: "pdf_word_records", name: "dictionary_frequency", definition: "INTEGER")
        ensureColumn(table: "web_word_records", name: "dictionary_frequency", definition: "INTEGER")
        ensureColumn(table: "pdf_vocabulary_words", name: "lemma", definition: "TEXT")
        ensureColumn(table: "pdf_vocabulary_occurrences", name: "surface_form", definition: "TEXT")
        ensureColumn(table: "pdf_vocabulary_occurrences", name: "text_anchor_json", definition: "TEXT")
    }

    private func ensureColumn(table: String, name: String, definition: String) {
        SQLiteSchemaMigrator.ensureColumn(
            db: db,
            table: table,
            name: name,
            definition: definition,
            logFailure: logSQLiteFailure,
            execute: { [weak self] sql, operation in
                self?.executeRaw(sql, operation: operation) ?? false
            }
        )
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func beginTransaction() -> Bool {
        executeRaw("BEGIN IMMEDIATE TRANSACTION", operation: "begin transaction")
    }

    private func commitTransaction() -> Bool {
        executeRaw("COMMIT", operation: "commit transaction")
    }

    private func rollbackTransaction() {
        executeRaw("ROLLBACK", operation: "rollback transaction")
    }

    private func execute(sql: String, bindings: [String], operation: String) -> Bool {
        executeStatement(
            sql: sql,
            prepareOperation: "prepare \(operation)",
            stepOperation: operation
        ) { statement in
            for (offset, value) in bindings.enumerated() {
                sqlite3_bind_text(statement, Int32(offset + 1), value, -1, WORD_RECORD_SQLITE_TRANSIENT)
            }
        }
    }

    private func loadRecords<Record>(
        sql: String,
        prepareOperation: String,
        bind: (OpaquePointer?) -> Void,
        decode: (OpaquePointer?) -> Record?
    ) -> [Record] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            logSQLiteFailure(prepareOperation)
            return []
        }
        defer { sqlite3_finalize(statement) }
        bind(statement)

        var records: [Record] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let record = decode(statement) else { continue }
            records.append(record)
        }
        return records
    }

    private func executeStatement(
        sql: String,
        prepareOperation: String,
        stepOperation: String,
        bind: (OpaquePointer?) -> Void
    ) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            logSQLiteFailure(prepareOperation)
            return false
        }
        defer { sqlite3_finalize(statement) }
        bind(statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            logSQLiteFailure(stepOperation)
            return false
        }
        return true
    }

    private func insertNormalizedPDFRecord(documentID: String, record: StoredPDFWordRecord) -> Bool {
        let canonicalKey = VocabularyTextPolicy.canonicalVocabularyKey(record.vocabularyGroupingText)
        guard !canonicalKey.isEmpty else { return false }
        let vocabularyID: String
        if let existing = existingPDFVocabularyID(documentID: documentID, canonicalKey: canonicalKey) {
            vocabularyID = existing
        } else if let preferred = record.vocabularyID {
            let existingKey = pdfVocabularyCanonicalKey(documentID: documentID, vocabularyID: preferred)
            vocabularyID = existingKey == nil || existingKey == canonicalKey
                ? preferred
                : UUID().uuidString
        } else {
            vocabularyID = UUID().uuidString
        }
        let srsJSON = codec.encode(record.srs)

        guard executeStatement(
            sql: """
            INSERT OR IGNORE INTO pdf_vocabulary_words(
                document_id, id, canonical_key, word, lemma, question, answer,
                dictionary_tags, dictionary_frequency, created_at, srs_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            prepareOperation: "prepare insert PDF vocabulary word",
            stepOperation: "insert PDF vocabulary word",
            bind: { statement in
            bindSQLiteText(documentID, index: 1, statement: statement)
            bindSQLiteText(vocabularyID, index: 2, statement: statement)
            bindSQLiteText(canonicalKey, index: 3, statement: statement)
            bindSQLiteText(record.word, index: 4, statement: statement)
            bindSQLiteOptionalText(record.lemma, index: 5, statement: statement)
            bindSQLiteText(record.question, index: 6, statement: statement)
            bindSQLiteText(record.answer, index: 7, statement: statement)
            bindSQLiteOptionalText(record.dictionaryTags, index: 8, statement: statement)
            bindSQLiteOptionalInt(record.dictionaryFrequency, index: 9, statement: statement)
            sqlite3_bind_double(statement, 10, record.createdAt.timeIntervalSince1970)
            bindSQLiteOptionalText(srsJSON, index: 11, statement: statement)
            }
        ) else {
            return false
        }

        let hasDefinition = !record.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !record.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let updateSQL = hasDefinition
            ? """
              UPDATE pdf_vocabulary_words
              SET lemma = COALESCE(?, lemma), question = ?, answer = ?, dictionary_tags = ?, dictionary_frequency = ?, srs_json = COALESCE(?, srs_json)
              WHERE document_id = ? AND id = ?
              """
            : """
              UPDATE pdf_vocabulary_words
              SET lemma = COALESCE(?, lemma),
                  dictionary_tags = COALESCE(?, dictionary_tags),
                  dictionary_frequency = COALESCE(?, dictionary_frequency),
                  srs_json = COALESCE(?, srs_json)
              WHERE document_id = ? AND id = ?
              """
        guard executeStatement(
            sql: updateSQL,
            prepareOperation: "prepare update PDF vocabulary word",
            stepOperation: "update PDF vocabulary word",
            bind: { statement in
            if hasDefinition {
                bindSQLiteOptionalText(record.lemma, index: 1, statement: statement)
                bindSQLiteText(record.question, index: 2, statement: statement)
                bindSQLiteText(record.answer, index: 3, statement: statement)
                bindSQLiteOptionalText(record.dictionaryTags, index: 4, statement: statement)
                bindSQLiteOptionalInt(record.dictionaryFrequency, index: 5, statement: statement)
                bindSQLiteOptionalText(srsJSON, index: 6, statement: statement)
                bindSQLiteText(documentID, index: 7, statement: statement)
                bindSQLiteText(vocabularyID, index: 8, statement: statement)
            } else {
                bindSQLiteOptionalText(record.lemma, index: 1, statement: statement)
                bindSQLiteOptionalText(record.dictionaryTags, index: 2, statement: statement)
                bindSQLiteOptionalInt(record.dictionaryFrequency, index: 3, statement: statement)
                bindSQLiteOptionalText(srsJSON, index: 4, statement: statement)
                bindSQLiteText(documentID, index: 5, statement: statement)
                bindSQLiteText(vocabularyID, index: 6, statement: statement)
            }
            }
        ) else {
            return false
        }

        return executeStatement(
            sql: """
            INSERT OR REPLACE INTO pdf_vocabulary_occurrences(
                document_id, id, vocabulary_id, location_key, page_index, bounds_json,
                text_anchor_json, context, surface_form, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            prepareOperation: "prepare insert PDF vocabulary occurrence",
            stepOperation: "insert PDF vocabulary occurrence",
            bind: { statement in
            bindSQLiteText(documentID, index: 1, statement: statement)
            bindSQLiteText(record.id, index: 2, statement: statement)
            bindSQLiteText(vocabularyID, index: 3, statement: statement)
            bindSQLiteText(pdfLocationKey(record: record), index: 4, statement: statement)
            sqlite3_bind_int(statement, 5, Int32(record.pageIndex))
            bindSQLiteText(codec.encode(record.bounds) ?? "{}", index: 6, statement: statement)
            bindSQLiteOptionalText(codec.encode(record.textAnchor), index: 7, statement: statement)
            bindSQLiteOptionalText(record.context, index: 8, statement: statement)
            bindSQLiteText(record.occurrenceSurfaceForm, index: 9, statement: statement)
            sqlite3_bind_double(statement, 10, record.createdAt.timeIntervalSince1970)
            }
        )
    }

    private func existingPDFVocabularyID(documentID: String, canonicalKey: String) -> String? {
        queryString(
            sql: "SELECT id FROM pdf_vocabulary_words WHERE document_id = ? AND canonical_key = ? LIMIT 1",
            bindings: [documentID, canonicalKey]
        )
    }

    private func pdfVocabularyCanonicalKey(documentID: String, vocabularyID: String) -> String? {
        queryString(
            sql: "SELECT canonical_key FROM pdf_vocabulary_words WHERE document_id = ? AND id = ? LIMIT 1",
            bindings: [documentID, vocabularyID]
        )
    }

    private func deleteOrphanedPDFVocabularyWords(documentID: String) -> Bool {
        execute(
            sql: """
            DELETE FROM pdf_vocabulary_words
            WHERE document_id = ?
              AND id NOT IN (
                SELECT vocabulary_id FROM pdf_vocabulary_occurrences WHERE document_id = ?
              )
            """,
            bindings: [documentID, documentID],
            operation: "delete orphaned PDF vocabulary words"
        )
    }

    private func pdfLocationKey(pageIndex: Int, bounds: CGRect) -> String {
        "\(pageIndex):\(Int(bounds.origin.x.rounded())):\(Int(bounds.origin.y.rounded())):\(Int(bounds.width.rounded())):\(Int(bounds.height.rounded()))"
    }

    private func pdfLocationKey(record: StoredPDFWordRecord) -> String {
        if let anchor = record.textAnchor {
            return "text:\(anchor.unitOrdinal):\(anchor.sourceStart):\(anchor.sourceLength)"
        }
        return pdfLocationKey(pageIndex: record.pageIndex, bounds: record.bounds.cgRect)
    }

    private func migrateLegacyPDFRecordsIfNeeded() {
        let migrationKey = "pdf_vocabulary_words_v2"
        if queryString(
            sql: "SELECT value FROM word_record_schema_metadata WHERE key = ? LIMIT 1",
            bindings: [migrationKey]
        ) == "1" {
            return
        }

        var statement: OpaquePointer?
        let sql = """
        SELECT id, word, page_index, bounds_json, context, question, answer,
               dictionary_tags, dictionary_frequency, created_at, srs_json, document_id
        FROM pdf_word_records
        ORDER BY document_id ASC, created_at ASC, id ASC
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            logSQLiteFailure("prepare legacy PDF vocabulary migration")
            return
        }
        var legacyRecords: [(documentID: String, record: StoredPDFWordRecord)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let record = pdfMapper.decode(from: statement),
                  let documentID = stringColumn(statement, 11) else {
                continue
            }
            legacyRecords.append((documentID, record))
        }
        sqlite3_finalize(statement)

        guard beginTransaction() else { return }
        var vocabularyIDs: [String: String] = [:]
        for item in legacyRecords {
            var record = item.record
            let canonicalKey = VocabularyTextPolicy.canonicalVocabularyKey(record.word)
            let groupingKey = item.documentID + "\u{1F}" + canonicalKey
            let vocabularyID = vocabularyIDs[groupingKey] ?? record.id
            vocabularyIDs[groupingKey] = vocabularyID
            record.vocabularyID = vocabularyID
            guard insertNormalizedPDFRecord(documentID: item.documentID, record: record) else {
                rollbackTransaction()
                return
            }
        }
        guard executeStatement(
            sql: "INSERT OR REPLACE INTO word_record_schema_metadata(key, value) VALUES (?, '1')",
            prepareOperation: "prepare PDF vocabulary migration marker",
            stepOperation: "save PDF vocabulary migration marker",
            bind: { bindSQLiteText(migrationKey, index: 1, statement: $0) }
        ) else {
            rollbackTransaction()
            return
        }
        guard commitTransaction() else {
            rollbackTransaction()
            return
        }
    }

    private func insertWebRecord(
        documentID: String,
        record: StoredWebWordRecord,
        prepareOperation: String = "prepare upsert web record",
        stepOperation: String = "upsert web record"
    ) -> Bool {
        executeStatement(
            sql: WebWordRecordSQLiteMapper.insertSQL,
            prepareOperation: prepareOperation,
            stepOperation: stepOperation
        ) { statement in
            webMapper.bind(documentID: documentID, record: record, to: statement)
        }
    }

    private func deleteRecords(table: String, documentID: String, ids: [String]) -> Bool {
        guard !ids.isEmpty else { return true }
        let sql = "DELETE FROM \(table) WHERE document_id = ? AND id = ?"
        guard beginTransaction() else { return false }
        var didFail = false
        for id in ids {
            let didDelete = executeStatement(
                sql: sql,
                prepareOperation: "prepare delete \(table) record",
                stepOperation: "delete \(table) record"
            ) { statement in
                sqlite3_bind_text(statement, 1, documentID, -1, WORD_RECORD_SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, id, -1, WORD_RECORD_SQLITE_TRANSIENT)
            }
            if !didDelete {
                didFail = true
            }
            if didFail { break }
        }
        if didFail {
            rollbackTransaction()
            return false
        }
        guard commitTransaction() else {
            rollbackTransaction()
            return false
        }
        return true
    }

    private func queryString(sql: String, bindings: [String]) -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            logSQLiteFailure("prepare string query")
            return nil
        }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in bindings.enumerated() {
            bindSQLiteText(value, index: Int32(offset + 1), statement: statement)
        }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return stringColumn(statement, 0)
    }

    private func bindSQLiteText(_ value: String, index: Int32, statement: OpaquePointer?) {
        sqlite3_bind_text(statement, index, value, -1, WORD_RECORD_SQLITE_TRANSIENT)
    }

    private func bindSQLiteOptionalText(_ value: String?, index: Int32, statement: OpaquePointer?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        bindSQLiteText(value, index: index, statement: statement)
    }

    private func bindSQLiteOptionalInt(_ value: Int?, index: Int32, statement: OpaquePointer?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_int(statement, index, Int32(value))
    }

    @discardableResult
    private func executeRaw(_ sql: String, operation: String) -> Bool {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if result == SQLITE_OK {
            return true
        }
        let message = errorMessage.map { String(cString: $0) } ?? sqliteErrorMessage()
        if let errorMessage {
            sqlite3_free(errorMessage)
        }
        NSLog("LeafReader word records: SQLite %@ failed (%d, error=%@)", operation, result, message)
        return false
    }

    private func logSQLiteFailure(_ operation: String) {
        NSLog("LeafReader word records: SQLite %@ failed (error=%@)", operation, sqliteErrorMessage())
    }

    private func sqliteErrorMessage() -> String {
        guard let db else { return "database is not open" }
        return String(cString: sqlite3_errmsg(db))
    }

    private static func databaseDirectory() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(AppIdentity.applicationSupportDirectoryName, isDirectory: true)
    }

    private static func defaultDatabaseURL() -> URL? {
        databaseDirectory()?.appendingPathComponent("word-records.sqlite3")
    }
}
