import Foundation
import NaturalLanguage
import LeafReaderCore

/// Per-session cache of built export records, keyed by document.
///
/// Even with the persistent label cache, rebuilding a document still costs a
/// SQLite load plus one indexed label read per record and the record-struct
/// construction. When a document's stored vocabulary has not changed since it
/// was last built this session, none of that work is needed — the previously
/// built records are still correct — so they are returned as-is.
///
/// Correctness rests entirely on the fingerprint: it must change whenever
/// anything that affects the built output changes. `VocabularyLibraryBuildCache`
/// itself never decides freshness; it only compares fingerprints the caller
/// supplies.
/// Thread-safe through `lock`; callers intentionally share this cache between
/// the main actor and background library rebuilds.
final class VocabularyLibraryBuildCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: (fingerprint: Int, records: [VocabularyExportRecord])] = [:]

    /// Returns the cached records for `documentID` when `fingerprint` matches the
    /// stored one, otherwise runs `build`, stores its result, and returns it.
    ///
    /// `build` runs outside the lock so a slow rebuild never blocks another
    /// document's lookup. Two concurrent rebuilds of the same document are
    /// harmless — both produce equal output and the later write wins.
    func records(
        documentID: String,
        fingerprint: Int,
        build: () -> [VocabularyExportRecord]
    ) -> [VocabularyExportRecord] {
        lock.lock()
        let cached = entries[documentID]
        lock.unlock()
        if let cached, cached.fingerprint == fingerprint {
            return cached.records
        }

        let built = build()
        lock.lock()
        entries[documentID] = (fingerprint, built)
        lock.unlock()
        return built
    }

    func invalidate(documentID: String) {
        lock.lock()
        entries[documentID] = nil
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    /// A cheap fingerprint over everything that changes the built output: the set
    /// of records (adds/deletes shift the count and ids), their mutable fields
    /// (answer/lemma/surface/context/tags edits), the label generation (a
    /// fetched flexion table can relabel forms without touching any record), and
    /// the language (which decides both the lemmatizer and which labeler runs,
    /// so the same records build different output under a different language).
    ///
    /// `Hasher` uses a per-process seed, which is fine: this cache lives only for
    /// the session, so the fingerprint only has to be stable within one run.
    static func fingerprint(
        pdf: [StoredPDFWordRecord],
        web: [StoredWebWordRecord],
        labelGeneration: Int,
        language: NLLanguage
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(labelGeneration)
        hasher.combine(language.rawValue)
        hasher.combine(pdf.count)
        for record in pdf {
            hasher.combine(record.id)
            hasher.combine(record.createdAt)
            hasher.combine(record.word)
            hasher.combine(record.lemma)
            hasher.combine(record.surfaceForm)
            hasher.combine(record.answer)
            hasher.combine(record.context)
            hasher.combine(record.dictionaryTags)
            hasher.combine(record.dictionaryFrequency)
        }
        hasher.combine(web.count)
        for record in web {
            hasher.combine(record.id)
            hasher.combine(record.createdAt)
            hasher.combine(record.word)
            hasher.combine(record.vocabularyID)
            hasher.combine(record.lemma)
            hasher.combine(record.surfaceForm)
            hasher.combine(record.answer)
            hasher.combine(record.context)
            hasher.combine(record.dictionaryTags)
            hasher.combine(record.dictionaryFrequency)
        }
        return hasher.finalize()
    }
}
