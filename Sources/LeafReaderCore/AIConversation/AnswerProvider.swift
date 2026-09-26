import Foundation

package struct AnswerProviderRequest {
    package let text: String
    package let context: String
    package let linkID: String?
    package let sourceLanguage: VocabularyLanguageID?
    package let lexicalItemID: VocabularyLexicalItemID?

    package init(
        text: String,
        context: String,
        linkID: String?,
        sourceLanguage: VocabularyLanguageID?,
        lexicalItemID: VocabularyLexicalItemID? = nil
    ) {
        self.text = text
        self.context = context
        self.linkID = linkID
        self.sourceLanguage = sourceLanguage
        self.lexicalItemID = lexicalItemID
    }
}

package struct AnswerProviderResult: Equatable {
    package enum Source: Equatable {
        case cachedVocabulary
        case localDictionary
    }

    package let answer: String
    package let source: Source
    package let dictionaryMetadata: VocabularyDictionaryMetadata?

    package init(answer: String, source: Source, dictionaryMetadata: VocabularyDictionaryMetadata? = nil) {
        self.answer = answer
        self.source = source
        self.dictionaryMetadata = dictionaryMetadata
    }
}

package protocol AnswerProvider {
    func answer(for request: AnswerProviderRequest) -> AnswerProviderResult?
}

package struct CachedVocabularyAnswerProvider: AnswerProvider {
    package let answerForLinkID: (String) -> String?

    package init(answerForLinkID: @escaping (String) -> String?) {
        self.answerForLinkID = answerForLinkID
    }

    package func answer(for request: AnswerProviderRequest) -> AnswerProviderResult? {
        guard let linkID = request.linkID,
              let answer = answerForLinkID(linkID)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !answer.isEmpty else {
            return nil
        }
        return AnswerProviderResult(answer: answer, source: .cachedVocabulary)
    }
}

package struct LocalDictionaryAnswerProvider: AnswerProvider {
    package let definitionProvider: any VocabularyDefinitionProviding

    package init(definitionProvider: any VocabularyDefinitionProviding) {
        self.definitionProvider = definitionProvider
    }

    package func answer(for request: AnswerProviderRequest) -> AnswerProviderResult? {
        guard let sourceLanguage = request.sourceLanguage,
              VocabularyTextPolicy.isSingleVocabularyWord(request.text),
              definitionProvider.descriptor.supports(sourceLanguage),
              let definition = definitionProvider.cachedDefinition(for: VocabularyDefinitionRequest(
                language: sourceLanguage,
                lemma: request.text,
                surfaceForm: request.text,
                context: request.context,
                lexicalItemID: request.lexicalItemID
              )) else { return nil }
        return AnswerProviderResult(
            answer: definition.markdown,
            source: .localDictionary,
            dictionaryMetadata: VocabularyDictionaryMetadata(
                tags: definition.tags,
                frequency: definition.frequency
            )
        )
    }
}

package struct CompositeAnswerProvider: AnswerProvider {
    package let providers: [AnswerProvider]

    package func answer(for request: AnswerProviderRequest) -> AnswerProviderResult? {
        for provider in providers {
            if let answer = provider.answer(for: request) {
                return answer
            }
        }
        return nil
    }
}
