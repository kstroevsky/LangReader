import Foundation

/// Provider-neutral request for the fallible linguistic evidence used by
/// language-specific form-label policies. The language profile owns routing;
/// native analyzers only answer the request for that already-resolved language.
package struct VocabularyFormLabelEvidenceRequest: Sendable, Equatable {
    package let surface: String
    package let context: String?
    package let language: VocabularyLanguageID
    package let auxiliaryLemmas: Set<String>
    package let allowsTrailingAuxiliary: Bool

    package init(
        surface: String,
        context: String?,
        language: VocabularyLanguageID,
        auxiliaryLemmas: Set<String>,
        allowsTrailingAuxiliary: Bool
    ) {
        self.surface = surface
        self.context = context
        self.language = language
        self.auxiliaryLemmas = auxiliaryLemmas
        self.allowsTrailingAuxiliary = allowsTrailingAuxiliary
    }
}

/// Evidence intentionally contains no native framework types. Missing evidence
/// is represented by nil/false and causes the Core policies to abstain.
package struct VocabularyFormLabelEvidence: Sendable, Equatable {
    package let partOfSpeech: String?
    package let hasClauseAuxiliary: Bool

    package init(partOfSpeech: String?, hasClauseAuxiliary: Bool) {
        self.partOfSpeech = partOfSpeech
        self.hasClauseAuxiliary = hasClauseAuxiliary
    }

    package static let unavailable = VocabularyFormLabelEvidence(
        partOfSpeech: nil,
        hasClauseAuxiliary: false
    )
}

package typealias VocabularyFormLabelEvidenceProvider = @Sendable (
    VocabularyFormLabelEvidenceRequest
) -> VocabularyFormLabelEvidence

/// A label verdict plus whether it is safe to persist independently of the
/// occurrence context that produced it.
package enum VocabularyFormLabelResolution: Equatable, Sendable {
    case contextIndependent(WordFormLabel?)
    case contextual(WordFormLabel?)

    package var label: WordFormLabel? {
        switch self {
        case let .contextIndependent(label), let .contextual(label):
            return label
        }
    }

    package var isPersistentlyCacheable: Bool {
        if case .contextIndependent = self { return true }
        return false
    }
}

