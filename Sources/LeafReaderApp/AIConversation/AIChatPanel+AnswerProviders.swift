import Foundation
import LeafReaderCore

extension AIChatPanel {
    func cachedVocabularyAnswer(
        for word: String,
        routingContext: VocabularyDefinitionRoutingContext?
    ) -> AnswerProviderResult? {
        guard let language = routingContext?.language,
              let answer = onVocabularyAnswerRequested?(word, language)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !answer.isEmpty else { return nil }
        return AnswerProviderResult(answer: answer, source: .cachedVocabulary)
    }

    func cachedLocalDictionaryAnswer(
        for request: AnswerProviderRequest,
        routingContext: VocabularyDefinitionRoutingContext?
    ) -> AnswerProviderResult? {
        guard let routingContext,
              request.sourceLanguage == routingContext.language,
              let provider = routingContext.provider else { return nil }
        return LocalDictionaryAnswerProvider(definitionProvider: provider).answer(for: request)
    }

    func localDictionaryTagSuffix(fallbackMetadata: VocabularyDictionaryMetadata?) -> String? {
        guard let fallbackMetadata else { return nil }
        return VocabularyTagFormatter.suffix(for: fallbackMetadata.tags)
    }
}
