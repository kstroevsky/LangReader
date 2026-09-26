import Foundation
import LeafReaderCore

// Bridges language-routed form labeling to the persistent label cache.
//
// Kept apart from `VocabularyFormLabeling` (pure routing) for the same reason
// `GermanCachedFormLabeling` is kept apart from `GermanFormLabeler`: the
// offline test binaries build the routing and the labelers without SQLite.
extension VocabularyFormLabeling {
    /// Offline resolver shaped for `VocabularyRecordProvider.records`.
    static func offlineFormLabelResolver(
        runtime: VocabularyLanguageRuntime?
    ) -> VocabularyRecordProvider.FormLabelResolver {
        guard let runtime,
              runtime.status(for: .formLabels).isAvailable,
              hasLabeler(for: runtime.language) else {
            return { _, _, _ in nil }
        }
        return { surfaceForm, lemma, context in
            label(
                surfaceForm: surfaceForm,
                lemma: lemma,
                context: context,
                language: runtime.language,
                evidenceProvider: runtime.formLabelEvidenceProvider
            )
        }
    }

    /// Cache-backed resolver shaped for `VocabularyRecordProvider.records`.
    ///
    /// German keeps its Wiktionary-flexion refinement; other languages use the
    /// persistent offline-label cache alone, which is the expensive half.
    static func persistentCachedFormLabelResolver(
        runtime: VocabularyLanguageRuntime?
    ) -> VocabularyRecordProvider.FormLabelResolver {
        guard let runtime,
              runtime.status(for: .formLabels).isAvailable,
              hasLabeler(for: runtime.language) else {
            return { _, _, _ in nil }
        }
        if runtime.language == .german {
            return { surfaceForm, lemma, context in
                GermanFormLabeler.persistentCachedLabel(
                    surfaceForm: surfaceForm,
                    lemma: lemma,
                    context: context,
                    language: runtime.language,
                    evidenceIdentity: runtime.formLabelEvidenceIdentity,
                    evidenceProvider: runtime.formLabelEvidenceProvider
                )
            }
        }
        return { surfaceForm, lemma, context in
            persistentCachedLabel(
                surfaceForm: surfaceForm,
                lemma: lemma,
                context: context,
                runtime: runtime
            )
        }
    }

    /// Like `GermanFormLabeler.persistentCachedLabel`, but for languages with no
    /// flexion tier: context-independent offline labels are memoized in SQLite.
    /// Language, provider evidence identity, and ruleset version are explicit
    /// cache dimensions, so equal spellings cannot cross language/provider lines.
    static func persistentCachedLabel(
        surfaceForm: String,
        lemma: String,
        context: String? = nil,
        runtime: VocabularyLanguageRuntime,
        labelStore: WordRecordSQLiteStore = .shared
    ) -> WordFormLabel? {
        let language = runtime.language
        let surfaceKey = VocabularyTextPolicy.canonicalVocabularyKey(surfaceForm)
        let lemmaKey = VocabularyTextPolicy.canonicalVocabularyKey(lemma)
        let version = labelingVersion(for: language)
        let cacheable = !surfaceKey.isEmpty && !lemmaKey.isEmpty

        if cacheable,
           let hit = labelStore.vocabularyFormLabel(
               language: language,
               evidenceIdentity: runtime.formLabelEvidenceIdentity,
               surfaceKey: surfaceKey,
               lemmaKey: lemmaKey,
               rulesetVersion: version
           ) {
            return hit.label.flatMap(WordFormLabel.init(rawValue:))
        }

        let resolution: VocabularyFormLabelResolution
        switch language {
        case .english:
            resolution = EnglishFormLabeler.resolution(
                surfaceForm: surfaceForm,
                lemma: lemma,
                context: context,
                evidenceProvider: runtime.formLabelEvidenceProvider
            )
        case .german:
            resolution = GermanFormLabeler.resolution(
                surfaceForm: surfaceForm,
                lemma: lemma,
                context: context,
                evidenceProvider: runtime.formLabelEvidenceProvider
            )
        default:
            return nil
        }
        if cacheable, resolution.isPersistentlyCacheable {
            labelStore.saveVocabularyFormLabel(
                language: language,
                evidenceIdentity: runtime.formLabelEvidenceIdentity,
                surfaceKey: surfaceKey,
                lemmaKey: lemmaKey,
                label: resolution.label?.rawValue,
                rulesetVersion: version
            )
        }
        return resolution.label
    }
}
