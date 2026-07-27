import Foundation
import LeafReaderCore

// Bridges the persistent flexion cache to form labeling.
//
// Kept apart from both GermanFlexionStore (pure storage) and
// GermanFlexionLabeling (pure table-to-label mapping) so neither of those
// files has to depend on the other: the offline test binaries build the
// mapping without SQLite, and the storage tests build the store without the
// NaturalLanguage-backed labeler.
extension GermanFormLabeler {

    /// Cache-backed resolver shaped for `VocabularyRecordProvider.records`.
    ///
    /// A plain reference to `cachedLabel` cannot be used there: Swift drops
    /// default arguments when a function is passed as a value, so the store
    /// and optional context have to be bound explicitly here.
    static let cachedFormLabelResolver: (String, String, String) -> GermanFormLabel? = {
        surfaceForm, lemma, context in
        cachedLabel(surfaceForm: surfaceForm, lemma: lemma, context: context)
    }

    /// Labels a surface form from the cached flexion tables, falling back to
    /// the offline rules.
    ///
    /// The cache wins when it has an answer because it resolves what the
    /// offline rules provably cannot: Präsens versus Präteritum, and plurals
    /// spelled identically to a genitive or dative singular. When the cache is
    /// empty — the common case until a word has been looked up — behavior is
    /// exactly the offline path.
    static func cachedLabel(
        surfaceForm: String,
        lemma: String,
        context: String? = nil,
        store: GermanFlexionStore = .shared
    ) -> GermanFormLabel? {
        if let refined = flexionLabel(surfaceForm: surfaceForm, lemma: lemma, store: store) {
            return refined
        }
        return label(surfaceForm: surfaceForm, lemma: lemma, context: context)
    }

    /// The label a cached flexion paradigm proves for this surface form, or nil
    /// when no paradigm covers it. This is the flexion-derived half of
    /// `cachedLabel`, split out so the persistent cache can compose it fresh on
    /// every read instead of freezing it — see `persistentCachedLabel`.
    static func flexionLabel(
        surfaceForm: String,
        lemma: String,
        store: GermanFlexionStore = .shared
    ) -> GermanFormLabel? {
        let cached = store.matches(surfaceForm: surfaceForm)
        guard !cached.isEmpty else { return nil }
        let lemmaKey = VocabularyTextPolicy.canonicalVocabularyKey(lemma)
        // Prefer parameters from the lemma this form was filed under; a spelling
        // shared by two lemmas must not borrow the other's label.
        let relevant = cached.filter {
            VocabularyTextPolicy.canonicalVocabularyKey($0.lemma) == lemmaKey
        }
        let candidates = relevant.isEmpty ? cached : relevant
        return resolve(parameters: candidates.map(\.parameter))
    }

    /// Resolver shaped for `VocabularyRecordProvider.records`, backed by the
    /// persistent label cache.
    static let persistentCachedFormLabelResolver: (String, String, String) -> GermanFormLabel? = {
        surfaceForm, lemma, context in
        persistentCachedLabel(surfaceForm: surfaceForm, lemma: lemma, context: context)
    }

    /// Like `cachedLabel`, but the expensive half is memoized across relaunches
    /// in SQLite.
    ///
    /// Only the **offline** label is cached. That is the costly part — a
    /// NaturalLanguage tag over the context sentence — and it depends solely on
    /// `(surface, lemma, context)`, so once computed it never has to run again.
    /// "No label" is stored too (as an empty string), because the ambiguous
    /// forms that resolve to nothing are exactly the ones the tagger spends the
    /// most time on.
    ///
    /// The flexion refinement is deliberately **not** cached: it is composed
    /// fresh on every read from a single indexed lookup. Caching it would make a
    /// stored label depend on the flexion table and require invalidating it when
    /// a paradigm is fetched — an invalidation that races a concurrent build and
    /// can strand a coarse label. Reading flexion live sidesteps that entirely: a
    /// paradigm fetched after this form was first labeled takes effect on the
    /// next read, with no invalidation and no race.
    static func persistentCachedLabel(
        surfaceForm: String,
        lemma: String,
        context: String? = nil,
        labelStore: WordRecordSQLiteStore = .shared,
        flexionStore: GermanFlexionStore = .shared
    ) -> GermanFormLabel? {
        // Flexion wins when it covers the form, and is always read fresh.
        if let refined = flexionLabel(surfaceForm: surfaceForm, lemma: lemma, store: flexionStore) {
            return refined
        }

        let surfaceKey = VocabularyTextPolicy.canonicalVocabularyKey(surfaceForm)
        let lemmaKey = VocabularyTextPolicy.canonicalVocabularyKey(lemma)
        let cacheable = !surfaceKey.isEmpty && !lemmaKey.isEmpty

        if cacheable,
           let hit = labelStore.germanFormLabel(
               surfaceKey: surfaceKey,
               lemmaKey: lemmaKey,
               version: labelingVersion
           ) {
            return hit.label.flatMap(GermanFormLabel.init(rawValue:))
        }

        let offline = label(surfaceForm: surfaceForm, lemma: lemma, context: context)
        if cacheable {
            labelStore.saveGermanFormLabel(
                surfaceKey: surfaceKey,
                lemmaKey: lemmaKey,
                label: offline?.rawValue,
                version: labelingVersion
            )
        }
        return offline
    }
}
