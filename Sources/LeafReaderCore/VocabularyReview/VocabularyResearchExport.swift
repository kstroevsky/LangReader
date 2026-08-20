import Foundation
import SQLite3

private let VOCABULARY_RESEARCH_SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

package struct VocabularyResearchProfile: Codable, Equatable, Sendable {
    package let participantPseudonym: String
    package let firstLanguageCode: String?
    package let selfRatedProficiency: String?

    package init(
        participantPseudonym: String,
        firstLanguageCode: String? = nil,
        selfRatedProficiency: String? = nil
    ) {
        self.participantPseudonym = participantPseudonym
        self.firstLanguageCode = firstLanguageCode?.nilIfTrimmedEmpty
        self.selfRatedProficiency = selfRatedProficiency?.nilIfTrimmedEmpty
    }
}

package struct VocabularyResearchEvidenceRecord: Codable, Equatable, Sendable {
    package let languageCode: String
    package let lexicalItemID: VocabularyLexicalItemID
    package let documentDomain: VocabularyDocumentDomain
    package let difficultyMean: Double
    package let difficultyStandardDeviation: Double
    package let difficultySource: VocabularyItemDifficultySource
    package let difficultyVersion: String
    package let evidence: VocabularyKnowledgeEvidence
    package let protocolVersion: Int
    package let sessionOrdinal: Int

    package init(
        languageCode: String,
        lexicalItemID: VocabularyLexicalItemID,
        documentDomain: VocabularyDocumentDomain,
        difficultyMean: Double,
        difficultyStandardDeviation: Double,
        difficultySource: VocabularyItemDifficultySource,
        difficultyVersion: String,
        evidence: VocabularyKnowledgeEvidence,
        protocolVersion: Int,
        sessionOrdinal: Int
    ) {
        self.languageCode = languageCode
        self.lexicalItemID = lexicalItemID
        self.documentDomain = documentDomain
        self.difficultyMean = difficultyMean
        self.difficultyStandardDeviation = difficultyStandardDeviation
        self.difficultySource = difficultySource
        self.difficultyVersion = difficultyVersion
        self.evidence = evidence
        self.protocolVersion = protocolVersion
        self.sessionOrdinal = sessionOrdinal
    }
}

package struct VocabularyResearchExport: Codable, Equatable, Sendable {
    package static let currentSchemaVersion = 1
    package let schemaVersion: Int
    package let participant: VocabularyResearchProfile
    package let records: [VocabularyResearchEvidenceRecord]

    package init(participant: VocabularyResearchProfile, records: [VocabularyResearchEvidenceRecord]) {
        schemaVersion = Self.currentSchemaVersion
        self.participant = participant
        self.records = records.sorted {
            if $0.languageCode != $1.languageCode { return $0.languageCode < $1.languageCode }
            if $0.sessionOrdinal != $1.sessionOrdinal { return $0.sessionOrdinal < $1.sessionOrdinal }
            return $0.lexicalItemID.canonicalKey < $1.lexicalItemID.canonicalKey
        }
    }

    package func encoded(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys]
        return try encoder.encode(self)
    }
}

package protocol VocabularyResearchEvidenceStoring: Sendable {
    @discardableResult
    func recordCompletedSession(
        contributionID: String,
        inventory: DocumentVocabularyInventory,
        answers: [VocabularyAssessmentAnswer],
        protocolVersion: Int
    ) -> Bool
    func export(profile: VocabularyResearchProfile) -> VocabularyResearchExport
    func recordCount() -> Int
}

/// Local-only storage. It intentionally contains no document identity, title,
/// path, context, definition, typed response, or exact timestamp.
package final class VocabularyResearchEvidenceStore: VocabularyResearchEvidenceStoring, @unchecked Sendable {
    package static let shared = VocabularyResearchEvidenceStore(databaseURL: defaultDatabaseURL())

    private let lock = NSLock()
    private var database: OpaquePointer?

    package init(databaseURL: URL?) {
        guard let databaseURL else { return }
        try? FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            sqlite3_close(database)
            database = nil
            return
        }
        execute("PRAGMA journal_mode = WAL")
        execute("""
        CREATE TABLE IF NOT EXISTS vocabulary_research_sessions (
            contribution_id TEXT PRIMARY KEY,
            language_code TEXT NOT NULL,
            session_ordinal INTEGER NOT NULL,
            document_domain TEXT NOT NULL,
            protocol_version INTEGER NOT NULL,
            UNIQUE(language_code, session_ordinal)
        )
        """)
        execute("""
        CREATE TABLE IF NOT EXISTS vocabulary_research_evidence (
            contribution_id TEXT NOT NULL,
            item_order INTEGER NOT NULL,
            language_code TEXT NOT NULL,
            lemma TEXT NOT NULL,
            part_of_speech TEXT NOT NULL,
            sense_key TEXT,
            document_domain TEXT NOT NULL,
            difficulty_mean REAL NOT NULL,
            difficulty_sd REAL NOT NULL,
            difficulty_source TEXT NOT NULL,
            difficulty_version TEXT NOT NULL,
            evidence TEXT NOT NULL,
            protocol_version INTEGER NOT NULL,
            session_ordinal INTEGER NOT NULL,
            PRIMARY KEY(contribution_id, item_order)
        )
        """)
    }

    deinit { sqlite3_close(database) }

    @discardableResult
    package func recordCompletedSession(
        contributionID: String,
        inventory: DocumentVocabularyInventory,
        answers: [VocabularyAssessmentAnswer],
        protocolVersion: Int
    ) -> Bool {
        lock.withLock {
            guard let database, !contributionID.isEmpty else { return false }
            let byKey = Dictionary(uniqueKeysWithValues: inventory.candidates.map { ($0.canonicalKey, $0) })
            let exportable = answers.compactMap { answer -> (VocabularyAssessmentAnswer, DocumentVocabularyCandidate)? in
                guard let candidate = byKey[answer.canonicalKey] else { return nil }
                return (answer, candidate)
            }
            guard !exportable.isEmpty else { return true }
            guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil) == SQLITE_OK else { return false }
            if sessionExists(contributionID: contributionID) {
                sqlite3_exec(database, "COMMIT", nil, nil, nil)
                return true
            }
            let ordinal = nextOrdinal(languageCode: inventory.languageCode)
            guard insertSession(
                contributionID: contributionID,
                languageCode: inventory.languageCode,
                ordinal: ordinal,
                domain: inventory.documentDomain,
                protocolVersion: protocolVersion
            ) else {
                sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
                return false
            }
            for (index, pair) in exportable.enumerated() where !insertEvidence(
                contributionID: contributionID,
                order: index,
                answer: pair.0,
                candidate: pair.1,
                inventory: inventory,
                ordinal: ordinal,
                protocolVersion: protocolVersion
            ) {
                sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
                return false
            }
            return sqlite3_exec(database, "COMMIT", nil, nil, nil) == SQLITE_OK
        }
    }

    package func export(profile: VocabularyResearchProfile) -> VocabularyResearchExport {
        lock.withLock {
            guard let database else { return VocabularyResearchExport(participant: profile, records: []) }
            var statement: OpaquePointer?
            let sql = """
            SELECT language_code, lemma, part_of_speech, sense_key, document_domain,
                   difficulty_mean, difficulty_sd, difficulty_source, difficulty_version,
                   evidence, protocol_version, session_ordinal
            FROM vocabulary_research_evidence
            ORDER BY language_code, session_ordinal, item_order
            """
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                return VocabularyResearchExport(participant: profile, records: [])
            }
            defer { sqlite3_finalize(statement) }
            var records: [VocabularyResearchEvidenceRecord] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let language = text(statement, 0),
                  let lemma = text(statement, 1),
                  let posRaw = text(statement, 2),
                  let domainRaw = text(statement, 4),
                  let sourceRaw = text(statement, 7),
                  let difficultyVersion = text(statement, 8),
                  let evidenceRaw = text(statement, 9),
                  let partOfSpeech = VocabularyPartOfSpeech(rawValue: posRaw),
                  let domain = VocabularyDocumentDomain(rawValue: domainRaw),
                  let source = VocabularyItemDifficultySource(rawValue: sourceRaw),
                  let evidence = VocabularyKnowledgeEvidence(rawValue: evidenceRaw) else { continue }
                records.append(VocabularyResearchEvidenceRecord(
                    languageCode: language,
                    lexicalItemID: VocabularyLexicalItemID(
                        language: language,
                        lemma: lemma,
                        partOfSpeech: partOfSpeech,
                        senseKey: text(statement, 3)
                    ),
                    documentDomain: domain,
                    difficultyMean: sqlite3_column_double(statement, 5),
                    difficultyStandardDeviation: sqlite3_column_double(statement, 6),
                    difficultySource: source,
                    difficultyVersion: difficultyVersion,
                    evidence: evidence,
                    protocolVersion: Int(sqlite3_column_int(statement, 10)),
                    sessionOrdinal: Int(sqlite3_column_int(statement, 11))
                ))
            }
            return VocabularyResearchExport(participant: profile, records: records)
        }
    }

    package func recordCount() -> Int {
        lock.withLock {
            guard let database else { return 0 }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM vocabulary_research_evidence", -1, &statement, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(statement) }
            return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int(statement, 0)) : 0
        }
    }

    private func sessionExists(contributionID: String) -> Bool {
        guard let database else { return false }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT 1 FROM vocabulary_research_sessions WHERE contribution_id = ?", -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        bind(contributionID, at: 1, to: statement)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func nextOrdinal(languageCode: String) -> Int {
        guard let database else { return 1 }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT COALESCE(MAX(session_ordinal), 0) + 1 FROM vocabulary_research_sessions WHERE language_code = ?", -1, &statement, nil) == SQLITE_OK else { return 1 }
        defer { sqlite3_finalize(statement) }
        bind(languageCode, at: 1, to: statement)
        return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int(statement, 0)) : 1
    }

    private func insertSession(
        contributionID: String,
        languageCode: String,
        ordinal: Int,
        domain: VocabularyDocumentDomain,
        protocolVersion: Int
    ) -> Bool {
        guard let database else { return false }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT INTO vocabulary_research_sessions VALUES (?, ?, ?, ?, ?)", -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        bind(contributionID, at: 1, to: statement)
        bind(languageCode, at: 2, to: statement)
        sqlite3_bind_int(statement, 3, Int32(ordinal))
        bind(domain.rawValue, at: 4, to: statement)
        sqlite3_bind_int(statement, 5, Int32(protocolVersion))
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func insertEvidence(
        contributionID: String,
        order: Int,
        answer: VocabularyAssessmentAnswer,
        candidate: DocumentVocabularyCandidate,
        inventory: DocumentVocabularyInventory,
        ordinal: Int,
        protocolVersion: Int
    ) -> Bool {
        guard let database else { return false }
        let lexical = candidate.lexicalItemID ?? VocabularyLexicalItemID(
            language: inventory.languageCode,
            lemma: candidate.lemmaKey,
            partOfSpeech: candidate.partOfSpeech
        )
        var statement: OpaquePointer?
        let placeholders = Array(repeating: "?", count: 14).joined(separator: ", ")
        guard sqlite3_prepare_v2(database, "INSERT INTO vocabulary_research_evidence VALUES (\(placeholders))", -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        bind(contributionID, at: 1, to: statement)
        sqlite3_bind_int(statement, 2, Int32(order))
        bind(inventory.languageCode, at: 3, to: statement)
        bind(lexical.lemma, at: 4, to: statement)
        bind(lexical.partOfSpeech.rawValue, at: 5, to: statement)
        if let sense = lexical.senseKey { bind(sense, at: 6, to: statement) } else { sqlite3_bind_null(statement, 6) }
        bind(inventory.documentDomain.rawValue, at: 7, to: statement)
        sqlite3_bind_double(statement, 8, candidate.difficultyPrior.mean)
        sqlite3_bind_double(statement, 9, candidate.difficultyPrior.standardDeviation)
        bind(candidate.difficultyPrior.source.rawValue, at: 10, to: statement)
        bind(candidate.difficultyPrior.version, at: 11, to: statement)
        bind(answer.evidence.rawValue, at: 12, to: statement)
        sqlite3_bind_int(statement, 13, Int32(protocolVersion))
        sqlite3_bind_int(statement, 14, Int32(ordinal))
        return sqlite3_step(statement) == SQLITE_DONE
    }

    @discardableResult private func execute(_ sql: String) -> Bool {
        guard let database else { return false }
        return sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK
    }

    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer?) {
        sqlite3_bind_text(statement, index, value, -1, VOCABULARY_RESEARCH_SQLITE_TRANSIENT)
    }

    private func text(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }

    private static func defaultDatabaseURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(AppIdentity.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("personal-vocabulary.sqlite3")
    }
}

package struct VocabularyItemCalibrationPack: Codable, Equatable, Sendable {
    package struct Item: Codable, Equatable, Sendable {
        package let lexicalItemID: VocabularyLexicalItemID
        package let difficulty: Double
        package let standardError: Double
        package let independentLearnerCount: Int
        package let hasMaterialDIF: Bool

        package init(
            lexicalItemID: VocabularyLexicalItemID,
            difficulty: Double,
            standardError: Double,
            independentLearnerCount: Int,
            hasMaterialDIF: Bool
        ) {
            self.lexicalItemID = lexicalItemID
            self.difficulty = difficulty
            self.standardError = standardError
            self.independentLearnerCount = independentLearnerCount
            self.hasMaterialDIF = hasMaterialDIF
        }

        package var isProductionEligible: Bool {
            independentLearnerCount >= 100 && standardError <= 0.35 && !hasMaterialDIF
        }
    }

    package let version: String
    package let reviewed: Bool
    package let model: String
    package let items: [Item]

    package init(version: String, reviewed: Bool, model: String, items: [Item]) {
        self.version = version
        self.reviewed = reviewed
        self.model = model
        self.items = items
    }

    package var productionItemsByKey: [String: Item] {
        guard reviewed, model == "rasch" else { return [:] }
        return Dictionary(uniqueKeysWithValues: items.filter(\.isProductionEligible).map {
            ($0.lexicalItemID.canonicalKey, $0)
        })
    }
}

package enum VocabularyItemCalibrationPackLoader {
    /// Only explicitly reviewed bundled packs are returned. Research-tool
    /// output starts with reviewed=false and is inert by construction.
    package static func loadReviewed(
        languageCode: String,
        resourceURLs: [URL]? = nil
    ) -> VocabularyItemCalibrationPack? {
        let urls: [URL]
        if let resourceURLs {
            urls = resourceURLs
        } else {
            var roots: [URL] = []
            if let resources = Bundle.main.resourceURL {
                roots.append(resources.appendingPathComponent("VocabularyCalibration", isDirectory: true))
            }
            roots.append(
                URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent("Sources/LeafReaderApp/Resources/VocabularyCalibration", isDirectory: true)
            )
            urls = roots.map { $0.appendingPathComponent("\(languageCode.lowercased()).json") }
        }
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            guard let data = try? Data(contentsOf: url),
                  let pack = try? JSONDecoder().decode(VocabularyItemCalibrationPack.self, from: data),
                  pack.reviewed,
                  pack.model == "rasch" else { continue }
            return pack
        }
        return nil
    }
}

private extension String {
    var nilIfTrimmedEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
