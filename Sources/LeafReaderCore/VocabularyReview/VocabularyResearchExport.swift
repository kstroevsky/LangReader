import Foundation
import SQLite3

private let VOCABULARY_RESEARCH_SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

package enum VocabularySelfRatedProficiency: String, CaseIterable, Codable, Equatable, Sendable {
    case a1A2 = "A1/A2"
    case b1B2 = "B1/B2"
    case c1C2 = "C1/C2"
    case unknown = "Unknown / prefer not to say"
}

package struct VocabularyResearchProfile: Codable, Equatable, Sendable {
    package let participantPseudonym: String
    package let firstLanguageCode: String?
    package let selfRatedProficiency: VocabularySelfRatedProficiency?

    package init(
        participantPseudonym: String,
        firstLanguageCode: String? = nil,
        selfRatedProficiency: VocabularySelfRatedProficiency? = nil
    ) {
        self.participantPseudonym = participantPseudonym
        self.firstLanguageCode = firstLanguageCode?.nilIfTrimmedEmpty
        self.selfRatedProficiency = selfRatedProficiency
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
    package let compatibilityFingerprint: VocabularyPreparationCompatibilityFingerprint?
    package let compatibilityFingerprintDigest: String?

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
        sessionOrdinal: Int,
        compatibilityFingerprint: VocabularyPreparationCompatibilityFingerprint? = nil,
        compatibilityFingerprintDigest: String? = nil
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
        self.compatibilityFingerprint = compatibilityFingerprint
        self.compatibilityFingerprintDigest = compatibilityFingerprintDigest
    }
}

package struct VocabularyResearchExport: Codable, Equatable, Sendable {
    package static let currentSchemaVersion = 3
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
    @discardableResult
    func recordCompletedSession(
        contributionID: String,
        inventory: DocumentVocabularyInventory,
        answers: [VocabularyAssessmentAnswer],
        protocolVersion: Int,
        compatibilityFingerprint: VocabularyPreparationCompatibilityFingerprint
    ) -> Bool
    func export(profile: VocabularyResearchProfile) -> VocabularyResearchExport
    func recordCount() -> Int
}

package extension VocabularyResearchEvidenceStoring {
    @discardableResult
    func recordCompletedSession(
        contributionID: String,
        inventory: DocumentVocabularyInventory,
        answers: [VocabularyAssessmentAnswer],
        protocolVersion: Int,
        compatibilityFingerprint: VocabularyPreparationCompatibilityFingerprint
    ) -> Bool {
        recordCompletedSession(
            contributionID: contributionID,
            inventory: inventory,
            answers: answers,
            protocolVersion: protocolVersion
        )
    }
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
            compatibility_fingerprint_json TEXT,
            compatibility_fingerprint_digest TEXT,
            UNIQUE(language_code, session_ordinal)
        )
        """)
        execute("ALTER TABLE vocabulary_research_sessions ADD COLUMN compatibility_fingerprint_json TEXT")
        execute("ALTER TABLE vocabulary_research_sessions ADD COLUMN compatibility_fingerprint_digest TEXT")
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
        recordCompletedSession(
            contributionID: contributionID,
            inventory: inventory,
            answers: answers,
            protocolVersion: protocolVersion,
            compatibilityFingerprint: nil
        )
    }

    @discardableResult
    package func recordCompletedSession(
        contributionID: String,
        inventory: DocumentVocabularyInventory,
        answers: [VocabularyAssessmentAnswer],
        protocolVersion: Int,
        compatibilityFingerprint: VocabularyPreparationCompatibilityFingerprint
    ) -> Bool {
        recordCompletedSession(
            contributionID: contributionID,
            inventory: inventory,
            answers: answers,
            protocolVersion: protocolVersion,
            compatibilityFingerprint: Optional(compatibilityFingerprint)
        )
    }

    private func recordCompletedSession(
        contributionID: String,
        inventory: DocumentVocabularyInventory,
        answers: [VocabularyAssessmentAnswer],
        protocolVersion: Int,
        compatibilityFingerprint: VocabularyPreparationCompatibilityFingerprint?
    ) -> Bool {
        lock.withLock {
            guard let database, !contributionID.isEmpty else { return false }
            let compatibilityJSON: String?
            if let compatibilityFingerprint {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                guard let data = try? encoder.encode(compatibilityFingerprint),
                      let json = String(data: data, encoding: .utf8) else { return false }
                compatibilityJSON = json
            } else {
                compatibilityJSON = nil
            }
            let byKey = Dictionary(uniqueKeysWithValues: inventory.candidates.map { ($0.canonicalKey, $0) })
            let exportable = answers.compactMap { answer -> (VocabularyAssessmentAnswer, DocumentVocabularyCandidate)? in
                guard let candidate = byKey[answer.canonicalKey],
                      candidate.lexicalItemID != nil else { return nil }
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
                protocolVersion: protocolVersion,
                compatibilityFingerprintJSON: compatibilityJSON,
                compatibilityFingerprintDigest: compatibilityFingerprint?.stableDigest
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
            SELECT e.language_code, e.lemma, e.part_of_speech, e.sense_key, e.document_domain,
                   e.difficulty_mean, e.difficulty_sd, e.difficulty_source, e.difficulty_version,
                   e.evidence, e.protocol_version, e.session_ordinal,
                   s.compatibility_fingerprint_json, s.compatibility_fingerprint_digest
            FROM vocabulary_research_evidence e
            JOIN vocabulary_research_sessions s ON s.contribution_id = e.contribution_id
            ORDER BY e.language_code, e.session_ordinal, e.item_order
            """
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                return VocabularyResearchExport(participant: profile, records: [])
            }
            defer { sqlite3_finalize(statement) }
            var records: [VocabularyResearchEvidenceRecord] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let language = text(statement, 0),
                  let languageID = VocabularyLanguageID(language),
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
                let storedDigest = text(statement, 13)
                let decodedFingerprint = text(statement, 12)
                    .flatMap { $0.data(using: .utf8) }
                    .flatMap { try? JSONDecoder().decode(VocabularyPreparationCompatibilityFingerprint.self, from: $0) }
                let compatibilityFingerprint: VocabularyPreparationCompatibilityFingerprint?
                let compatibilityFingerprintDigest: String?
                if let decodedFingerprint,
                   let storedDigest,
                   decodedFingerprint.stableDigest == storedDigest {
                    compatibilityFingerprint = decodedFingerprint
                    compatibilityFingerprintDigest = storedDigest
                } else {
                    compatibilityFingerprint = nil
                    compatibilityFingerprintDigest = nil
                }
                records.append(VocabularyResearchEvidenceRecord(
                    languageCode: language,
                    lexicalItemID: VocabularyLexicalItemID(
                        language: languageID,
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
                    sessionOrdinal: Int(sqlite3_column_int(statement, 11)),
                    compatibilityFingerprint: compatibilityFingerprint,
                    compatibilityFingerprintDigest: compatibilityFingerprintDigest
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
        protocolVersion: Int,
        compatibilityFingerprintJSON: String?,
        compatibilityFingerprintDigest: String?
    ) -> Bool {
        guard let database else { return false }
        var statement: OpaquePointer?
        let sql = """
        INSERT INTO vocabulary_research_sessions(
            contribution_id, language_code, session_ordinal, document_domain,
            protocol_version, compatibility_fingerprint_json, compatibility_fingerprint_digest
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        bind(contributionID, at: 1, to: statement)
        bind(languageCode, at: 2, to: statement)
        sqlite3_bind_int(statement, 3, Int32(ordinal))
        bind(domain.rawValue, at: 4, to: statement)
        sqlite3_bind_int(statement, 5, Int32(protocolVersion))
        if let compatibilityFingerprintJSON {
            bind(compatibilityFingerprintJSON, at: 6, to: statement)
        } else {
            sqlite3_bind_null(statement, 6)
        }
        if let compatibilityFingerprintDigest {
            bind(compatibilityFingerprintDigest, at: 7, to: statement)
        } else {
            sqlite3_bind_null(statement, 7)
        }
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
        guard let lexical = candidate.lexicalItemID else { return false }
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
    package let target: VocabularyCalibrationCompatibilityTarget?
    package let observationCompatibilityFingerprintDigest: String?
    package let items: [Item]

    package init(
        version: String,
        reviewed: Bool,
        model: String,
        target: VocabularyCalibrationCompatibilityTarget? = nil,
        observationCompatibilityFingerprintDigest: String? = nil,
        items: [Item]
    ) {
        self.version = version
        self.reviewed = reviewed
        self.model = model
        self.target = target
        self.observationCompatibilityFingerprintDigest = observationCompatibilityFingerprintDigest
        self.items = items
    }

    package var productionItemsByKey: [String: Item] {
        guard isStructurallyValid else { return [:] }
        return Dictionary(uniqueKeysWithValues: items.filter(\.isProductionEligible).map {
            ($0.lexicalItemID.canonicalKey, $0)
        })
    }

    fileprivate var isStructurallyValid: Bool {
        guard reviewed,
              model == "rasch",
              let target,
              observationCompatibilityFingerprintDigest?.isEmpty == false else {
            return false
        }
        var keys = Set<String>()
        for item in items {
            guard item.lexicalItemID.language == target.language,
                  item.difficulty.isFinite,
                  item.standardError.isFinite,
                  item.standardError >= 0,
                  item.independentLearnerCount >= 0,
                  keys.insert(item.lexicalItemID.canonicalKey).inserted else {
                return false
            }
        }
        return true
    }
}

package enum VocabularyItemCalibrationPackLoader {
    /// Only explicitly reviewed bundled packs are returned. Research-tool
    /// output starts with reviewed=false and is inert by construction.
    package static func loadReviewed(
        target: VocabularyCalibrationCompatibilityTarget,
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
            urls = roots.map { $0.appendingPathComponent("\(target.language.bcp47.lowercased()).json") }
        }
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            guard let data = try? Data(contentsOf: url),
                  let pack = try? JSONDecoder().decode(VocabularyItemCalibrationPack.self, from: data),
                  pack.target == target,
                  pack.isStructurallyValid else { continue }
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
