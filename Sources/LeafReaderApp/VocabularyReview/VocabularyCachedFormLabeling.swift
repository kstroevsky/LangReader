import Foundation
import NaturalLanguage
import LeafReaderCore

// Bridges language-routed form labeling to the persistent label cache.
//
// Kept apart from `VocabularyFormLabeling` (pure routing) for the same reason
// `GermanCachedFormLabeling` is kept apart from `GermanFormLabeler`: the
// offline test binaries build the routing and the labelers without SQLite.
extension VocabularyFormLabeling {
    /// Offline resolver shaped for `VocabularyRecordProvider.records`.
    static func offlineFormLabelResolver(
        language: NLLanguage
    ) -> VocabularyRecordProvider.FormLabelResolver {
        { surfaceForm, lemma, context in
            label(surfaceForm: surfaceForm, lemma: lemma, context: context, language: language)
        }
    }

    /// Cache-backed resolver shaped for `VocabularyRecordProvider.records`.
    ///
    /// German keeps its Wiktionary-flexion refinement; other languages use the
    /// persistent offline-label cache alone, which is the expensive half.
    static func persistentCachedFormLabelResolver(
        language: NLLanguage
    ) -> VocabularyRecordProvider.FormLabelResolver {
        if language == .german {
            return GermanFormLabeler.persistentCachedFormLabelResolver
        }
        guard hasLabeler(for: language) else { return { _, _, _ in nil } }
        return { surfaceForm, lemma, context in
            persistentCachedLabel(
                surfaceForm: surfaceForm,
                lemma: lemma,
                context: context,
                language: language
            )
        }
    }

    /// Like `GermanFormLabeler.persistentCachedLabel`, but for languages with no
    /// flexion tier: the offline label — the costly NaturalLanguage pass — is
    /// memoized in SQLite, keyed by the language's own cache version so two
    /// languages' labels for the same spelling can never be read as each other's.
    static func persistentCachedLabel(
        surfaceForm: String,
        lemma: String,
        context: String? = nil,
        language: NLLanguage,
        labelStore: WordRecordSQLiteStore = .shared
    ) -> WordFormLabel? {
        let surfaceKey = VocabularyTextPolicy.canonicalVocabularyKey(surfaceForm)
        let lemmaKey = VocabularyTextPolicy.canonicalVocabularyKey(lemma)
        let version = cacheVersion(for: language)
        let cacheable = !surfaceKey.isEmpty && !lemmaKey.isEmpty

        if cacheable,
           let hit = labelStore.germanFormLabel(
               surfaceKey: surfaceKey,
               lemmaKey: lemmaKey,
               version: version
           ) {
            return hit.label.flatMap(WordFormLabel.init(rawValue:))
        }

        let offline = label(surfaceForm: surfaceForm, lemma: lemma, context: context, language: language)
        if cacheable {
            labelStore.saveGermanFormLabel(
                surfaceKey: surfaceKey,
                lemmaKey: lemmaKey,
                label: offline?.rawValue,
                version: version
            )
        }
        return offline
    }
}
