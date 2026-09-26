import CryptoKit
import Foundation
import SQLite3

package struct VocabularyReaderPrior: Codable, Equatable, Sendable {
    package let languageCode: String
    package let thetaPosterior: [Double]
    package let completedSessionCount: Int
    package let verifiedEvidenceCount: Int
    package let lastUpdatedAt: Date
    package let algorithmVersion: Int
    package let compatibilityFingerprintDigest: String?

    package init(
        languageCode: String,
        thetaPosterior: [Double],
        completedSessionCount: Int,
        verifiedEvidenceCount: Int,
        lastUpdatedAt: Date,
        algorithmVersion: Int,
        compatibilityFingerprintDigest: String? = nil
    ) {
        self.languageCode = languageCode.lowercased()
        self.thetaPosterior = Self.normalized(thetaPosterior)
        self.completedSessionCount = max(0, completedSessionCount)
        self.verifiedEvidenceCount = max(0, verifiedEvidenceCount)
        self.lastUpdatedAt = lastUpdatedAt
        self.algorithmVersion = algorithmVersion
        self.compatibilityFingerprintDigest = compatibilityFingerprintDigest
    }

    package func isEligible(at date: Date = Date()) -> Bool {
        completedSessionCount >= 2
            && verifiedEvidenceCount >= 40
            && lastUpdatedAt <= date
            && date.timeIntervalSince(lastUpdatedAt) <= 180 * 24 * 60 * 60
            && thetaPosterior.count == 121
    }

    package func warmStartPosterior(
        thetaGrid: [Double],
        genericPrior: [Double],
        smoothingStandardDeviation: Double = 0.35,
        warmPriorWeight: Double = 0.90
    ) -> [Double]? {
        guard thetaPosterior.count == thetaGrid.count,
              genericPrior.count == thetaGrid.count,
              !thetaGrid.isEmpty else { return nil }
        let variance = smoothingStandardDeviation * smoothingStandardDeviation
        var smoothed = Array(repeating: 0.0, count: thetaGrid.count)
        for target in thetaGrid.indices {
            for source in thetaGrid.indices {
                let delta = thetaGrid[target] - thetaGrid[source]
                smoothed[target] += thetaPosterior[source] * exp(-(delta * delta) / (2 * variance))
            }
        }
        smoothed = Self.normalized(smoothed)
        let weight = min(max(warmPriorWeight, 0), 1)
        return Self.normalized(zip(smoothed, genericPrior).map {
            weight * $0.0 + (1 - weight) * $0.1
        })
    }

    private static func normalized(_ values: [Double]) -> [Double] {
        let finite = values.map { $0.isFinite && $0 > 0 ? $0 : 0 }
        let total = finite.reduce(0, +)
        guard total > 0 else { return values.isEmpty ? [] : Array(repeating: 1 / Double(values.count), count: values.count) }
        return finite.map { $0 / total }
    }
}

package struct VocabularyReaderPriorArchive: Equatable, Sendable {
    package let prior: VocabularyReaderPrior
    package let archivedAt: Date

    package init(prior: VocabularyReaderPrior, archivedAt: Date) {
        self.prior = prior
        self.archivedAt = archivedAt
    }
}

package struct VocabularyReaderPriorSummary: Equatable, Sendable {
    package let languageCode: String
    package let completedSessionCount: Int
    package let verifiedEvidenceCount: Int
    package let lastUpdatedAt: Date

    package init(
        languageCode: String,
        completedSessionCount: Int,
        verifiedEvidenceCount: Int,
        lastUpdatedAt: Date
    ) {
        self.languageCode = languageCode
        self.completedSessionCount = completedSessionCount
        self.verifiedEvidenceCount = verifiedEvidenceCount
        self.lastUpdatedAt = lastUpdatedAt
    }
}

package protocol VocabularyReaderPriorStoring: Sendable {
    func load(languageCode: String) -> VocabularyReaderPrior?
    func load(
        languageCode: String,
        compatibilityFingerprint: VocabularyPreparationCompatibilityFingerprint
    ) -> VocabularyReaderPrior?
    func summaries() -> [VocabularyReaderPriorSummary]
    @discardableResult
    func recordCompletedSession(
        contributionID: String,
        languageCode: String,
        thetaPosterior: [Double],
        verifiedEvidenceCount: Int,
        completedAt: Date,
        algorithmVersion: Int
    ) -> Bool
    @discardableResult
    func recordCompletedSession(
        contributionID: String,
        languageCode: String,
        thetaPosterior: [Double],
        verifiedEvidenceCount: Int,
        completedAt: Date,
        algorithmVersion: Int,
        compatibilityFingerprint: VocabularyPreparationCompatibilityFingerprint
    ) -> Bool
    @discardableResult func reset(languageCode: String) -> Bool
}

package extension VocabularyReaderPriorStoring {
    func load(
        languageCode: String,
        compatibilityFingerprint: VocabularyPreparationCompatibilityFingerprint
    ) -> VocabularyReaderPrior? {
        guard let prior = load(languageCode: languageCode),
              prior.compatibilityFingerprintDigest == compatibilityFingerprint.stableDigest else {
            return nil
        }
        return prior
    }

    @discardableResult
    func recordCompletedSession(
        contributionID: String,
        languageCode: String,
        thetaPosterior: [Double],
        verifiedEvidenceCount: Int,
        completedAt: Date,
        algorithmVersion: Int,
        compatibilityFingerprint: VocabularyPreparationCompatibilityFingerprint
    ) -> Bool {
        recordCompletedSession(
            contributionID: contributionID,
            languageCode: languageCode,
            thetaPosterior: thetaPosterior,
            verifiedEvidenceCount: verifiedEvidenceCount,
            completedAt: completedAt,
            algorithmVersion: algorithmVersion
        )
    }
}

package final class VocabularyReaderPriorStore: VocabularyReaderPriorStoring, @unchecked Sendable {
    package static let shared = VocabularyReaderPriorStore(databaseURL: defaultDatabaseURL())

    private let lock = NSLock()
    private var db: OpaquePointer?

    package init(databaseURL: URL?) {
        guard let databaseURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return
        }
        guard sqlite3_open_v2(
            databaseURL.path,
            &db,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            sqlite3_close(db)
            db = nil
            return
        }
        execute("PRAGMA journal_mode = WAL")
        execute("""
        CREATE TABLE IF NOT EXISTS vocabulary_reader_priors (
            language_code TEXT PRIMARY KEY,
            posterior_json TEXT NOT NULL,
            completed_sessions INTEGER NOT NULL,
            verified_evidence INTEGER NOT NULL,
            updated_at REAL NOT NULL,
            algorithm_version INTEGER NOT NULL,
            compatibility_fingerprint TEXT
        )
        """)
        // Existing databases predate semantic fingerprints. A duplicate-column
        // failure is expected after the first migration and can be ignored.
        execute("ALTER TABLE vocabulary_reader_priors ADD COLUMN compatibility_fingerprint TEXT")
        execute("""
        CREATE TABLE IF NOT EXISTS vocabulary_reader_prior_sessions (
            contribution_id TEXT PRIMARY KEY,
            language_code TEXT NOT NULL,
            completed_at REAL NOT NULL
        )
        """)
        execute("""
        CREATE TABLE IF NOT EXISTS vocabulary_reader_prior_archives (
            archive_identity TEXT PRIMARY KEY,
            language_code TEXT NOT NULL,
            archived_at REAL NOT NULL,
            prior_json BLOB NOT NULL
        )
        """)
    }

    deinit { sqlite3_close(db) }

    package func load(languageCode: String) -> VocabularyReaderPrior? {
        lock.withLock { loadLocked(languageCode: languageCode) }
    }

    package func load(
        languageCode: String,
        compatibilityFingerprint: VocabularyPreparationCompatibilityFingerprint
    ) -> VocabularyReaderPrior? {
        lock.withLock {
            guard let prior = loadLocked(languageCode: languageCode),
                  prior.compatibilityFingerprintDigest == compatibilityFingerprint.stableDigest else {
                return nil
            }
            return prior
        }
    }

    package func archivedPriors(languageCode: String) -> [VocabularyReaderPriorArchive] {
        lock.withLock {
            guard let db else { return [] }
            var statement: OpaquePointer?
            let sql = """
            SELECT archived_at, prior_json
            FROM vocabulary_reader_prior_archives
            WHERE language_code = ?
            ORDER BY archived_at, archive_identity
            """
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(statement) }
            bind(languageCode.lowercased(), at: 1, to: statement)
            var archives: [VocabularyReaderPriorArchive] = []
            while sqlite3_step(statement) == SQLITE_ROW,
                  let bytes = sqlite3_column_blob(statement, 1) {
                let count = Int(sqlite3_column_bytes(statement, 1))
                let data = Data(bytes: bytes, count: count)
                guard let prior = try? JSONDecoder().decode(VocabularyReaderPrior.self, from: data) else {
                    continue
                }
                archives.append(VocabularyReaderPriorArchive(
                    prior: prior,
                    archivedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0))
                ))
            }
            return archives
        }
    }

    package func summaries() -> [VocabularyReaderPriorSummary] {
        lock.withLock {
            guard let db else { return [] }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                db,
                "SELECT language_code, completed_sessions, verified_evidence, updated_at FROM vocabulary_reader_priors ORDER BY language_code",
                -1,
                &statement,
                nil
            ) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(statement) }
            var result: [VocabularyReaderPriorSummary] = []
            while sqlite3_step(statement) == SQLITE_ROW,
                  let language = sqlite3_column_text(statement, 0) {
                result.append(VocabularyReaderPriorSummary(
                    languageCode: String(cString: language),
                    completedSessionCount: Int(sqlite3_column_int(statement, 1)),
                    verifiedEvidenceCount: Int(sqlite3_column_int(statement, 2)),
                    lastUpdatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
                ))
            }
            return result
        }
    }

    @discardableResult
    package func recordCompletedSession(
        contributionID: String,
        languageCode: String,
        thetaPosterior: [Double],
        verifiedEvidenceCount: Int,
        completedAt: Date,
        algorithmVersion: Int
    ) -> Bool {
        recordCompletedSession(
            contributionID: contributionID,
            languageCode: languageCode,
            thetaPosterior: thetaPosterior,
            verifiedEvidenceCount: verifiedEvidenceCount,
            completedAt: completedAt,
            algorithmVersion: algorithmVersion,
            compatibilityFingerprintDigest: nil
        )
    }

    @discardableResult
    package func recordCompletedSession(
        contributionID: String,
        languageCode: String,
        thetaPosterior: [Double],
        verifiedEvidenceCount: Int,
        completedAt: Date,
        algorithmVersion: Int,
        compatibilityFingerprint: VocabularyPreparationCompatibilityFingerprint
    ) -> Bool {
        recordCompletedSession(
            contributionID: contributionID,
            languageCode: languageCode,
            thetaPosterior: thetaPosterior,
            verifiedEvidenceCount: verifiedEvidenceCount,
            completedAt: completedAt,
            algorithmVersion: algorithmVersion,
            compatibilityFingerprintDigest: compatibilityFingerprint.stableDigest
        )
    }

    private func recordCompletedSession(
        contributionID: String,
        languageCode: String,
        thetaPosterior: [Double],
        verifiedEvidenceCount: Int,
        completedAt: Date,
        algorithmVersion: Int,
        compatibilityFingerprintDigest: String?
    ) -> Bool {
        lock.withLock {
            guard let db,
                  !contributionID.isEmpty,
                  thetaPosterior.count == 121,
                  let data = try? JSONEncoder().encode(thetaPosterior),
                  let json = String(data: data, encoding: .utf8) else { return false }
            let languageCode = languageCode.lowercased()
            guard sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil) == SQLITE_OK else {
                return false
            }
            var contributionStatement: OpaquePointer?
            let contributionSQL = """
            INSERT OR IGNORE INTO vocabulary_reader_prior_sessions(
                contribution_id, language_code, completed_at
            ) VALUES (?, ?, ?)
            """
            guard sqlite3_prepare_v2(db, contributionSQL, -1, &contributionStatement, nil) == SQLITE_OK else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return false
            }
            bind(contributionID, at: 1, to: contributionStatement)
            bind(languageCode, at: 2, to: contributionStatement)
            sqlite3_bind_double(contributionStatement, 3, completedAt.timeIntervalSince1970)
            let contributionResult = sqlite3_step(contributionStatement)
            let insertedContribution = sqlite3_changes(db) == 1
            sqlite3_finalize(contributionStatement)
            guard contributionResult == SQLITE_DONE else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return false
            }
            guard insertedContribution else {
                sqlite3_exec(db, "COMMIT", nil, nil, nil)
                return true
            }
            let existing = loadLocked(languageCode: languageCode)
            let compatibleExisting = existing?.algorithmVersion == algorithmVersion
                && existing?.compatibilityFingerprintDigest == compatibilityFingerprintDigest
                ? existing
                : nil
            if let existing, compatibleExisting == nil,
               !archiveLocked(existing, archivedAt: Date()) {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return false
            }
            var statement: OpaquePointer?
            let sql = """
            INSERT OR REPLACE INTO vocabulary_reader_priors(
                language_code, posterior_json, completed_sessions, verified_evidence,
                updated_at, algorithm_version, compatibility_fingerprint
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return false
            }
            defer { sqlite3_finalize(statement) }
            bind(languageCode, at: 1, to: statement)
            bind(json, at: 2, to: statement)
            sqlite3_bind_int(
                statement,
                3,
                Int32((compatibleExisting?.completedSessionCount ?? 0) + 1)
            )
            sqlite3_bind_int(
                statement,
                4,
                Int32((compatibleExisting?.verifiedEvidenceCount ?? 0) + max(0, verifiedEvidenceCount))
            )
            sqlite3_bind_double(statement, 5, completedAt.timeIntervalSince1970)
            sqlite3_bind_int(statement, 6, Int32(algorithmVersion))
            if let compatibilityFingerprintDigest {
                bind(compatibilityFingerprintDigest, at: 7, to: statement)
            } else {
                sqlite3_bind_null(statement, 7)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return false
            }
            return sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK
        }
    }

    @discardableResult
    package func reset(languageCode: String) -> Bool {
        lock.withLock {
            guard let db else { return false }
            let languageCode = languageCode.lowercased()
            guard sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil) == SQLITE_OK else {
                return false
            }
            var contributionStatement: OpaquePointer?
            guard sqlite3_prepare_v2(
                db,
                "DELETE FROM vocabulary_reader_prior_sessions WHERE language_code = ?",
                -1,
                &contributionStatement,
                nil
            ) == SQLITE_OK else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return false
            }
            bind(languageCode, at: 1, to: contributionStatement)
            let removedContributions = sqlite3_step(contributionStatement) == SQLITE_DONE
            sqlite3_finalize(contributionStatement)
            guard removedContributions else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return false
            }
            var archiveStatement: OpaquePointer?
            guard sqlite3_prepare_v2(
                db,
                "DELETE FROM vocabulary_reader_prior_archives WHERE language_code = ?",
                -1,
                &archiveStatement,
                nil
            ) == SQLITE_OK else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return false
            }
            bind(languageCode, at: 1, to: archiveStatement)
            let removedArchives = sqlite3_step(archiveStatement) == SQLITE_DONE
            sqlite3_finalize(archiveStatement)
            guard removedArchives else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return false
            }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                db,
                "DELETE FROM vocabulary_reader_priors WHERE language_code = ?",
                -1,
                &statement,
                nil
            ) == SQLITE_OK else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return false
            }
            defer { sqlite3_finalize(statement) }
            bind(languageCode, at: 1, to: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return false
            }
            return sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK
        }
    }

    private func loadLocked(languageCode: String) -> VocabularyReaderPrior? {
        guard let db else { return nil }
        var statement: OpaquePointer?
        let sql = """
        SELECT posterior_json, completed_sessions, verified_evidence, updated_at,
               algorithm_version, compatibility_fingerprint
        FROM vocabulary_reader_priors WHERE language_code = ? LIMIT 1
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(languageCode.lowercased(), at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let json = sqlite3_column_text(statement, 0),
              let data = String(cString: json).data(using: .utf8),
              let posterior = try? JSONDecoder().decode([Double].self, from: data),
              posterior.count == 121 else { return nil }
        let compatibilityFingerprintDigest = sqlite3_column_type(statement, 5) == SQLITE_NULL
            ? nil
            : sqlite3_column_text(statement, 5).map { String(cString: $0) }
        return VocabularyReaderPrior(
            languageCode: languageCode,
            thetaPosterior: posterior,
            completedSessionCount: Int(sqlite3_column_int(statement, 1)),
            verifiedEvidenceCount: Int(sqlite3_column_int(statement, 2)),
            lastUpdatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
            algorithmVersion: Int(sqlite3_column_int(statement, 4)),
            compatibilityFingerprintDigest: compatibilityFingerprintDigest
        )
    }

    private func archiveLocked(_ prior: VocabularyReaderPrior, archivedAt: Date) -> Bool {
        guard let db else { return false }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(prior) else { return false }
        let archiveIdentity = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        var statement: OpaquePointer?
        let sql = """
        INSERT OR IGNORE INTO vocabulary_reader_prior_archives(
            archive_identity, language_code, archived_at, prior_json
        ) VALUES (?, ?, ?, ?)
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        bind(archiveIdentity, at: 1, to: statement)
        bind(prior.languageCode, at: 2, to: statement)
        sqlite3_bind_double(statement, 3, archivedAt.timeIntervalSince1970)
        let bindResult = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, 4, bytes.baseAddress, Int32(bytes.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard bindResult == SQLITE_OK else { return false }
        return sqlite3_step(statement) == SQLITE_DONE
    }

    @discardableResult
    private func execute(_ sql: String) -> Bool {
        guard let db else { return false }
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer?) {
        sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private static func defaultDatabaseURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(AppIdentity.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("personal-vocabulary.sqlite3")
    }
}
