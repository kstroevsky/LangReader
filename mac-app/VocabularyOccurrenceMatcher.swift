import Foundation

struct VocabularyTextOccurrence: Equatable {
    let range: NSRange
    let matchedText: String
}

enum VocabularyOccurrenceMatcher {
    static func matches(query: String, in text: String) -> [VocabularyTextOccurrence] {
        let normalizedQuery = VocabularyTextPolicy.normalizedVocabularyText(query)
        guard VocabularyTextPolicy.isVocabularySelection(normalizedQuery), !text.isEmpty else {
            return []
        }

        let queryKey = VocabularyTextPolicy.canonicalVocabularyKey(normalizedQuery)
        let patterns = occurrencePatterns(for: normalizedQuery)
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var seenRanges = Set<String>()
        var occurrences: [VocabularyTextOccurrence] = []

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: fullRange) {
                let rangeKey = "\(match.range.location):\(match.range.length)"
                guard !seenRanges.contains(rangeKey) else { continue }
                let matchedText = nsText.substring(with: match.range)
                let normalizedMatch = VocabularyTextPolicy.normalizedOccurrenceText(
                    matchedText,
                    matching: normalizedQuery
                )
                guard VocabularyTextPolicy.canonicalVocabularyKey(normalizedMatch) == queryKey else {
                    continue
                }
                seenRanges.insert(rangeKey)
                occurrences.append(VocabularyTextOccurrence(range: match.range, matchedText: matchedText))
            }
        }

        return occurrences.sorted { lhs, rhs in
            if lhs.range.location != rhs.range.location {
                return lhs.range.location < rhs.range.location
            }
            return lhs.range.length < rhs.range.length
        }
    }

    private static func occurrencePatterns(for query: String) -> [String] {
        var patterns: [String] = []
        for candidate in VocabularyTextPolicy.pdfSearchQueries(for: query) {
            if let pattern = VocabularyTextPolicy.boundedSearchPattern(for: candidate),
               !patterns.contains(pattern) {
                patterns.append(pattern)
            }
        }
        if let pattern = VocabularyTextPolicy.lineBrokenDehyphenatedSearchPattern(for: query),
           !patterns.contains(pattern) {
            patterns.append(pattern)
        }
        return patterns
    }
}
