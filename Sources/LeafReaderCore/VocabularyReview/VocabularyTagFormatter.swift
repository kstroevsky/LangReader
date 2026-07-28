import Foundation

package enum VocabularyTagFormatter {
    package static func suffix(for tags: String?) -> String? {
        let values = tagValues(from: tags)
        guard !values.isEmpty else { return nil }
        return "\n\n\(markdownText(for: tags) ?? "")"
    }

    package static func displayText(for tags: String?) -> String? {
        let values = tagValues(from: tags)
        guard !values.isEmpty else { return nil }
        return values.map { $0.uppercased() }.joined(separator: " ")
    }

    package static func markdownText(for tags: String?) -> String? {
        let values = tagValues(from: tags)
        guard !values.isEmpty else { return nil }
        return values.map { "`\($0.uppercased())`" }.joined(separator: " ")
    }

    package static func appendSuffix(to answer: String, suffix: String?) -> String {
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let suffix,
              !suffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return trimmedAnswer
        }
        return VocabularyAnswerSanitizer.removingTrailingTags(from: trimmedAnswer) + suffix
    }

    package static func tagValues(from tags: String?) -> [String] {
        String(tags ?? "")
            .components(separatedBy: CharacterSet(charactersIn: ",;/| ").union(.whitespacesAndNewlines))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "`").union(.whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
    }
}
