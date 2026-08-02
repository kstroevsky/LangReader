import Foundation

package struct VocabularyDictionaryMetadata: Equatable {
    package let tags: String?
    package let frequency: Int?

    package init(tags: String?, frequency: Int?) {
        self.tags = tags
        self.frequency = frequency
    }
}

package struct VocabularyDictionaryAnswer {
    package let markdown: String
    package let metadata: VocabularyDictionaryMetadata

    package init(markdown: String, metadata: VocabularyDictionaryMetadata) {
        self.markdown = markdown
        self.metadata = metadata
    }
}

package protocol DictionaryLookupService {
    func lookup(_ query: String) -> ECDICTEntry?
    func markdownAnswer(for query: String, context: String) -> String?
    func dictionaryAnswer(for query: String, context: String) -> VocabularyDictionaryAnswer?
    func cachedDictionaryAnswer(for query: String, context: String) -> VocabularyDictionaryAnswer?
    func metadata(for word: String) -> VocabularyDictionaryMetadata
}

extension DictionaryLookupService {
    package func cachedDictionaryAnswer(for query: String, context: String = "") -> VocabularyDictionaryAnswer? {
        nil
    }
}

/// Immutable after construction — its only stored property is a `let` reference
/// to the (Sendable) dictionary — so it is safe to share; `@unchecked` because
/// the conformance is on a class.
package final class LocalDictionaryLookupService: DictionaryLookupService, @unchecked Sendable {
    package static let shared = LocalDictionaryLookupService()

    private let dictionary: ECDICTDictionary

    package init(dictionary: ECDICTDictionary = .shared) {
        self.dictionary = dictionary
    }

    package func lookup(_ query: String) -> ECDICTEntry? {
        dictionary.lookup(query)
    }

    package func markdownAnswer(for query: String, context: String = "") -> String? {
        dictionary.markdownAnswer(for: query, context: context)
    }

    package func dictionaryAnswer(for query: String, context: String = "") -> VocabularyDictionaryAnswer? {
        guard let entry = lookup(query) else { return nil }
        return VocabularyDictionaryAnswer(
            markdown: ECDICTAnswerFormatter.markdownAnswer(for: entry, context: context),
            metadata: metadata(for: entry)
        )
    }

    package func cachedDictionaryAnswer(for query: String, context: String) -> VocabularyDictionaryAnswer? {
        guard let entry = dictionary.cachedLookupOnly(query) else { return nil }
        return VocabularyDictionaryAnswer(
            markdown: ECDICTAnswerFormatter.markdownAnswer(for: entry, context: context),
            metadata: metadata(for: entry)
        )
    }

    package func metadata(for word: String) -> VocabularyDictionaryMetadata {
        guard let entry = lookup(word) else {
            return VocabularyDictionaryMetadata(tags: nil, frequency: nil)
        }
        return metadata(for: entry)
    }

    private func metadata(for entry: ECDICTEntry) -> VocabularyDictionaryMetadata {
        let tags = entry.tags.trimmingCharacters(in: .whitespacesAndNewlines)
        return VocabularyDictionaryMetadata(
            tags: tags.isEmpty ? nil : tags,
            frequency: Self.frequency(from: entry.frq)
        )
    }

    private static func frequency(from value: String) -> Int? {
        guard let frequency = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)), frequency > 0 else {
            return nil
        }
        return frequency
    }
}
