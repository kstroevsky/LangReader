import Foundation
import NaturalLanguage

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
enum VocabularyFormLabeling {
    /// Whether labels can be produced for `language`.
    static func hasLabeler(for language: NLLanguage) -> Bool {
        language == .german || language == .english
    }

    /// The offline label for one surface form in `language`.
    static func label(
        surfaceForm: String,
        lemma: String,
        context: String?,
        language: NLLanguage
    ) -> WordFormLabel? {
        switch language {
        case .german:
            return GermanFormLabeler.label(surfaceForm: surfaceForm, lemma: lemma, context: context)
        case .english:
            return EnglishFormLabeler.label(surfaceForm: surfaceForm, lemma: lemma, context: context)
        default:
            return nil
        }
    }

    /// The labeling ruleset version for `language`, so a cached label produced
    /// by an older ruleset is treated as absent.
    static func labelingVersion(for language: NLLanguage) -> Int {
        switch language {
        case .german: return GermanFormLabeler.labelingVersion
        case .english: return EnglishFormLabeler.labelingVersion
        default: return 0
        }
    }

    /// Cache version namespaced by language.
    ///
    /// The label cache is keyed by (surface, lemma, version) with no language
    /// column, so the language is folded into the version. Without this, the
    /// same spelling in two languages — "was", "die", "hat" — would collide and
    /// serve one language's label to the other.
    static func cacheVersion(for language: NLLanguage) -> Int {
        let base = labelingVersion(for: language)
        switch language {
        case .german: return base
        case .english: return 1000 + base
        default: return -1
        }
    }
}
