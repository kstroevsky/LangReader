import Foundation

struct AnswerProviderRequest {
    let text: String
    let context: String
    let linkID: String?
}

struct AnswerProviderResult: Equatable {
    enum Source: Equatable {
        case cachedVocabulary
        case localDictionary
    }

    let answer: String
    let source: Source
    let dictionaryMetadata: VocabularyDictionaryMetadata?

    init(answer: String, source: Source, dictionaryMetadata: VocabularyDictionaryMetadata? = nil) {
        self.answer = answer
        self.source = source
        self.dictionaryMetadata = dictionaryMetadata
    }
}

protocol AnswerProvider {
    func answer(for request: AnswerProviderRequest) -> AnswerProviderResult?
}

struct CachedVocabularyAnswerProvider: AnswerProvider {
    let answerForLinkID: (String) -> String?

    func answer(for request: AnswerProviderRequest) -> AnswerProviderResult? {
        guard let linkID = request.linkID,
              let answer = answerForLinkID(linkID)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !answer.isEmpty else {
            return nil
        }
        return AnswerProviderResult(answer: answer, source: .cachedVocabulary)
    }
}

struct LocalDictionaryAnswerProvider: AnswerProvider {
    let dictionaryLookupService: DictionaryLookupService
    let isDictionaryInstalled: () -> Bool

    init(
        dictionaryLookupService: DictionaryLookupService = LocalDictionaryLookupService.shared,
        isDictionaryInstalled: @escaping () -> Bool = { ECDICTDictionary.shared.isInstalled }
    ) {
        self.dictionaryLookupService = dictionaryLookupService
        self.isDictionaryInstalled = isDictionaryInstalled
    }

    func answer(for request: AnswerProviderRequest) -> AnswerProviderResult? {
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

struct CompositeAnswerProvider: AnswerProvider {
    let providers: [AnswerProvider]

    func answer(for request: AnswerProviderRequest) -> AnswerProviderResult? {
        for provider in providers {
            if let answer = provider.answer(for: request) {
                return answer
            }
        }
        return nil
    }
}
