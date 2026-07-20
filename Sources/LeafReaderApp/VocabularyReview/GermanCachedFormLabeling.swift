import Foundation

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
        let cached = store.matches(surfaceForm: surfaceForm)
        if !cached.isEmpty {
            let lemmaKey = VocabularyTextPolicy.canonicalVocabularyKey(lemma)
            // Prefer parameters from the lemma this form was filed under; a
            // spelling shared by two lemmas must not borrow the other's label.
            let relevant = cached.filter {
                VocabularyTextPolicy.canonicalVocabularyKey($0.lemma) == lemmaKey
            }
            let candidates = relevant.isEmpty ? cached : relevant
            if let resolved = resolve(parameters: candidates.map(\.parameter)) {
                return resolved
            }
        }
        return label(surfaceForm: surfaceForm, lemma: lemma, context: context)
    }
}
