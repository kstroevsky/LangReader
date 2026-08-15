import Foundation
import SQLite3

private let GERMAN_FREQUENCY_SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Replaceable lookup boundary for the pinned German cold-start frequency
/// prior. The shipping table is immutable; access to its single SQLite handle
/// is serialized because assessments can be prepared on background queues.
package final class GermanFrequencyRankTable: @unchecked Sendable {
    package static let maximumRank = 200_000
    package static let shared = GermanFrequencyRankTable()

    private let databaseURLs: [URL]
    private let lock = NSLock()
    private var database: OpaquePointer?
    private var openedURL: URL?

    package init(databaseURLs: [URL]? = nil) {
        self.databaseURLs = databaseURLs ?? Self.defaultDatabaseURLs()
    }

    deinit {
        lock.lock()
        if let database { sqlite3_close(database) }
        database = nil
        openedURL = nil
        lock.unlock()
    }

    package var isInstalled: Bool {
        databaseURLs.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    package func rank(for word: String) -> Int? {
        let key = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        return lock.withLock {
            guard let database = openDatabase() else { return nil }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database,
                "SELECT rank FROM word_rank WHERE word_key = ? LIMIT 1",
                -1,
                &statement,
                nil
            ) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, key, -1, GERMAN_FREQUENCY_SQLITE_TRANSIENT)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return Int(sqlite3_column_int(statement, 0))
        }
    }

    package func bestRank(lemma: String, observedForms: [VocabularyDocumentObservedForm]) -> Int? {
        ([lemma] + observedForms.map(\.surface)).compactMap(rank(for:)).min()
    }

    package func rowCount() -> Int? {
        lock.withLock {
            guard let database = openDatabase() else { return nil }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM word_rank", -1, &statement, nil) == SQLITE_OK else {
                return nil
            }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return Int(sqlite3_column_int(statement, 0))
        }
    }

    private func openDatabase() -> OpaquePointer? {
        if let database { return database }
        guard let url = databaseURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { return nil }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            return nil
        }
        database = handle
        openedURL = url
        return handle
    }

    private static func defaultDatabaseURLs() -> [URL] {
        var roots: [URL] = []
        if let resources = Bundle.main.resourceURL {
            roots.append(resources.appendingPathComponent("GermanFrequency", isDirectory: true))
            roots.append(resources)
        }
        roots.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources/LeafReaderApp/Resources/GermanFrequency", isDirectory: true)
        )
        return roots.map { $0.appendingPathComponent("deu_news_2025_1M.sqlite") }
    }
}

package enum DocumentVocabularyFrequencyProvider {
    package static let englishMaximumRank = 43_336

    package static func englishBestRank(for summary: VocabularyDocumentLemmaSummary) -> Int? {
        ([summary.displayLemma] + summary.observedForms.map(\.surface))
            .compactMap { LocalDictionaryLookupService.shared.metadata(for: $0).frequency }
            .min()
    }

    package static func germanBestRank(for summary: VocabularyDocumentLemmaSummary) -> Int? {
        GermanFrequencyRankTable.shared.bestRank(
            lemma: summary.displayLemma,
            observedForms: summary.observedForms
        )
    }
}
