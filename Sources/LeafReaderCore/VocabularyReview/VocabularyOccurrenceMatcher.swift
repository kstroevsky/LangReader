import Foundation

package struct VocabularyTextOccurrence: Equatable {
    package let range: NSRange
    package let matchedText: String
}

package enum VocabularyOccurrenceMatcher {
    /// A query with its patterns already compiled.
    ///
    /// Scanning a document runs the same query against every page, so the
    /// regexes are built once here instead of being recompiled per page.
    package struct CompiledQuery {
        package let normalizedQuery: String
        package let queryKey: String
        package let regexes: [NSRegularExpression]
    }

    package static func compile(query: String) -> CompiledQuery? {
        let normalizedQuery = VocabularyTextPolicy.normalizedVocabularyText(query)
        guard VocabularyTextPolicy.isVocabularySelection(normalizedQuery) else { return nil }
        return CompiledQuery(
            normalizedQuery: normalizedQuery,
            queryKey: VocabularyTextPolicy.canonicalVocabularyKey(normalizedQuery),
            regexes: occurrencePatterns(for: normalizedQuery).compactMap {
                try? NSRegularExpression(pattern: $0)
            }
        )
    }

    package static func matches(query: String, in text: String) -> [VocabularyTextOccurrence] {
        guard let compiled = compile(query: query) else { return [] }
        return matches(compiled: compiled, in: text)
    }

    package static func matches(compiled: CompiledQuery, in text: String) -> [VocabularyTextOccurrence] {
        guard !text.isEmpty else { return [] }

        let normalizedQuery = compiled.normalizedQuery
        let queryKey = compiled.queryKey
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var seenRanges = Set<String>()
        var occurrences: [VocabularyTextOccurrence] = []

        for regex in compiled.regexes {
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
