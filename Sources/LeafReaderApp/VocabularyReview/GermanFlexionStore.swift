import Foundation

/// One inflected form as persisted in the flexion cache.
///
/// `parameter` keeps Wiktionary's own name (`Nominativ Plural`, `Partizip II`)
/// rather than a mapped label, so the stored data stays faithful to the source
/// and can be reinterpreted if the label vocabulary changes later.
struct StoredGermanFlexionForm: Equatable {
    let parameter: String
    let surface: String
    let isVariant: Bool
}

struct StoredGermanFlexion: Equatable {
    let lemma: String
    let genus: String?
    let auxiliary: String?
    let forms: [StoredGermanFlexionForm]
    let fetchedAt: Date

    var lemmaKey: String {
        VocabularyTextPolicy.canonicalVocabularyKey(lemma)
    }
}

/// A cached form matched by its surface spelling, carrying the lemma it belongs to.
struct StoredGermanFlexionMatch: Equatable {
    let lemma: String
    let parameter: String
    let surface: String
    let isVariant: Bool
}

/// Persistent store for German flexion tables.
///
/// Replaces the process-lifetime dictionary that previously held lookups, so a
/// table fetched once keeps working offline and across relaunches — the point
/// of the dictionary tier is that difficult forms stay resolved without
/// requiring the network again.
struct GermanFlexionStore {
    static let shared = GermanFlexionStore()

    private let store: WordRecordSQLiteStore

    init(store: WordRecordSQLiteStore = .shared) {
        self.store = store
    }

    @discardableResult
    func save(_ entry: StoredGermanFlexion) -> Bool {
        store.saveGermanFlexion(entry)
    }

    func hasEntry(forLemma lemma: String) -> Bool {
        store.hasGermanFlexion(
            lemmaKey: VocabularyTextPolicy.canonicalVocabularyKey(lemma)
        )
    }

    func matches(surfaceForm: String) -> [StoredGermanFlexionMatch] {
        store.germanFlexionMatches(surfaceForm: surfaceForm)
    }

    /// The lemma a surface form belongs to, when the cache knows it.
    ///
    /// Prefers a non-variant match so `Hause` reports `Haus` rather than being
    /// treated as a headword of its own. Returns nil when several lemmas claim
    /// the same spelling, since guessing between them would merge unrelated
    /// words — exactly the failure the grouping key is meant to avoid.
    func lemma(forSurfaceForm surfaceForm: String) -> String? {
        let matches = store.germanFlexionMatches(surfaceForm: surfaceForm)
        guard !matches.isEmpty else { return nil }
        let lemmas = Set(matches.map { VocabularyTextPolicy.canonicalVocabularyKey($0.lemma) })
        guard lemmas.count == 1 else { return nil }
        return matches.first { !$0.isVariant }?.lemma ?? matches.first?.lemma
    }

    /// Re-files vocabulary that was saved under one of this lemma's inflected
    /// spellings, now that the paradigm is known.
    ///
    /// Deliberately conservative. A form is only moved when the cache maps it
    /// to exactly one lemma, so a spelling shared by two words is left alone
    /// rather than merged into the wrong entry — the failure that keying on an
    /// unreliable signal would have caused.
    ///
    /// Call after `save`, so the lookup sees the entry that was just written.
    @discardableResult
    func regroupSavedVocabulary(for entry: StoredGermanFlexion) -> Int {
        let lemmaKey = entry.lemmaKey
        guard !lemmaKey.isEmpty else { return 0 }

        var handled: Set<String> = [lemmaKey]
        var regrouped = 0
        for form in entry.forms {
            let formKey = VocabularyTextPolicy.canonicalVocabularyKey(form.surface)
            guard !formKey.isEmpty, handled.insert(formKey).inserted else { continue }
            // Skip spellings another lemma also claims.
            guard let resolved = lemma(forSurfaceForm: form.surface),
                  VocabularyTextPolicy.canonicalVocabularyKey(resolved) == lemmaKey else {
                continue
            }
            regrouped += store.regroupVocabulary(
                fromKey: formKey,
                intoKey: lemmaKey,
                lemma: entry.lemma
            )
        }
        return regrouped
    }
}
