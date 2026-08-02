import Foundation

package struct AnswerProviderRequest {
    package let text: String
    package let context: String
    package let linkID: String?

    package init(text: String, context: String, linkID: String?) {
        self.text = text
        self.context = context
        self.linkID = linkID
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
    package let dictionaryLookupService: DictionaryLookupService
    package let isDictionaryInstalled: () -> Bool

    package init(
        dictionaryLookupService: DictionaryLookupService = LocalDictionaryLookupService.shared,
        isDictionaryInstalled: @escaping () -> Bool = { ECDICTDictionary.shared.isInstalled }
    ) {
        self.dictionaryLookupService = dictionaryLookupService
        self.isDictionaryInstalled = isDictionaryInstalled
    }

    package func answer(for request: AnswerProviderRequest) -> AnswerProviderResult? {
        guard VocabularyTextPolicy.isSingleEnglishWord(request.text) else { return nil }
        if let answer = dictionaryLookupService.dictionaryAnswer(for: request.text, context: request.context) {
            return AnswerProviderResult(
                answer: answer.markdown,
                source: .localDictionary,
                dictionaryMetadata: answer.metadata
            )
        }
        _ = isDictionaryInstalled()
        return nil
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
