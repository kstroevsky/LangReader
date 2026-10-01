import Foundation

/// Routes form labeling to the labeler for a document's language.
///
/// Each language brings its own grammar, so each gets its own labeler; this is
/// the single place that decides which one runs. Languages without a labeler
/// yield no labels at all rather than borrowing another language's grammar —
/// their forms still group and highlight, they simply show unlabeled.
///
/// Deliberately free of any storage dependency, like `GermanFormLabeler`: the
/// cache-backed resolvers live in `VocabularyCachedFormLabeling` so the offline
/// test binaries can build this routing without SQLite.
package enum VocabularyFormLabeling {
    /// Whether labels can be produced for `language`.
    package static func hasLabeler(for language: VocabularyLanguageID) -> Bool {
        language == .german || language == .english
    }

    /// The offline label for one surface form in `language`.
    package static func label(
        surfaceForm: String,
        lemma: String,
        context: String?,
        language: VocabularyLanguageID,
        evidenceProvider: @escaping VocabularyFormLabelEvidenceProvider = { _ in .unavailable }
    ) -> WordFormLabel? {
        switch language {
        case .german:
            return GermanFormLabeler.label(
                surfaceForm: surfaceForm,
                lemma: lemma,
                context: context,
                evidenceProvider: evidenceProvider
            )
        case .english:
            return EnglishFormLabeler.label(
                surfaceForm: surfaceForm,
                lemma: lemma,
                context: context,
                evidenceProvider: evidenceProvider
            )
        default: return nil
        }
    }

    /// The labeling ruleset version for `language`, so a cached label produced
    /// by an older ruleset is treated as absent.
    package static func labelingVersion(for language: VocabularyLanguageID) -> Int {
        switch language {
        case .german: return GermanFormLabeler.labelingVersion
        case .english: return EnglishFormLabeler.labelingVersion
        default: return 0
        }
    }

}
