import Foundation
import NaturalLanguage

enum GermanLemmaResolver {
    static func lemma(for surfaceForm: String) -> String {
        let word = VocabularyTextPolicy.normalizedVocabularyText(surfaceForm)
        guard VocabularyTextPolicy.isSingleEnglishWord(word),
              !word.isEmpty else { return word }

        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = word
        let fullRange = word.startIndex..<word.endIndex
        tagger.setLanguage(.german, range: fullRange)
        guard let tag = tagger.tag(
            at: word.startIndex,
            unit: .word,
            scheme: .lemma
        ).0 else {
            return word
        }
        let lemma = VocabularyTextPolicy.normalizedVocabularyText(tag.rawValue)
        guard VocabularyTextPolicy.isSingleEnglishWord(lemma) else { return word }
        return lemma
    }

    static func groupingKey(word: String, lemma: String? = nil) -> String {
        let trimmedLemma = lemma?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmedLemma.flatMap { value in
            value.isEmpty ? nil : value
        } ?? self.lemma(for: word)
        return VocabularyTextPolicy.canonicalVocabularyKey(resolved)
    }
}

enum GermanLemmaOccurrenceMatcher {
    static func matches(lemma rawLemma: String, selectedForm: String, in text: String) -> [VocabularyTextOccurrence] {
        let lemma = VocabularyTextPolicy.normalizedVocabularyText(rawLemma)
        let selected = VocabularyTextPolicy.normalizedVocabularyText(selectedForm)
        guard VocabularyTextPolicy.isSingleEnglishWord(lemma),
              VocabularyTextPolicy.isSingleEnglishWord(selected),
              !text.isEmpty else {
            return VocabularyOccurrenceMatcher.matches(query: selectedForm, in: text)
        }

        let lemmaKey = VocabularyTextPolicy.canonicalVocabularyKey(lemma)
        var occurrences = VocabularyOccurrenceMatcher.matches(query: selected, in: text)
        var seenRanges = Set(occurrences.map { "\($0.range.location):\($0.range.length)" })

        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        let fullRange = text.startIndex..<text.endIndex
        tagger.setLanguage(.german, range: fullRange)
        tagger.enumerateTags(
            in: fullRange,
            unit: .word,
            scheme: .lemma,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, tokenRange in
            let matchedText = String(text[tokenRange])
            let matchedLemma = tag.map { VocabularyTextPolicy.normalizedVocabularyText($0.rawValue) }
                ?? GermanLemmaResolver.lemma(for: matchedText)
            let surfaceKey = VocabularyTextPolicy.canonicalVocabularyKey(matchedText)
            let matchedLemmaKey = VocabularyTextPolicy.canonicalVocabularyKey(matchedLemma)
            guard surfaceKey == lemmaKey || matchedLemmaKey == lemmaKey else { return true }

            let range = NSRange(tokenRange, in: text)
            let rangeKey = "\(range.location):\(range.length)"
            guard seenRanges.insert(rangeKey).inserted else { return true }
            occurrences.append(VocabularyTextOccurrence(range: range, matchedText: matchedText))
            return true
        }

        if let lineWrapRegex = try? NSRegularExpression(
            pattern: #"\p{L}[\p{L}\p{M}]*[‐‑‒–—-]\s+\p{L}[\p{L}\p{M}]*"#
        ) {
            let nsText = text as NSString
            for match in lineWrapRegex.matches(
                in: text,
                range: NSRange(location: 0, length: nsText.length)
            ) {
                let rawMatch = nsText.substring(with: match.range)
                let normalizedMatch = VocabularyTextPolicy.normalizedOccurrenceText(
                    rawMatch,
                    matching: selected
                )
                let matchedLemmaKey = VocabularyTextPolicy.canonicalVocabularyKey(
                    GermanLemmaResolver.lemma(for: normalizedMatch)
                )
                let rangeKey = "\(match.range.location):\(match.range.length)"
                guard matchedLemmaKey == lemmaKey,
                      seenRanges.insert(rangeKey).inserted else { continue }
                occurrences.append(VocabularyTextOccurrence(range: match.range, matchedText: rawMatch))
            }
        }

        return occurrences.sorted {
            if $0.range.location != $1.range.location {
                return $0.range.location < $1.range.location
            }
            return $0.range.length < $1.range.length
        }
    }

    static func matches(lemmasByKey: [String: String], in text: String) -> [String: [VocabularyTextOccurrence]] {
        guard !lemmasByKey.isEmpty, !text.isEmpty else { return [:] }
        var occurrencesByKey: [String: [VocabularyTextOccurrence]] = [:]
        var seenRangesByKey: [String: Set<String>] = [:]

        func append(_ occurrence: VocabularyTextOccurrence, for key: String) {
            guard lemmasByKey[key] != nil else { return }
            let rangeKey = "\(occurrence.range.location):\(occurrence.range.length)"
            guard seenRangesByKey[key, default: []].insert(rangeKey).inserted else { return }
            occurrencesByKey[key, default: []].append(occurrence)
        }

        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        let fullRange = text.startIndex..<text.endIndex
        tagger.setLanguage(.german, range: fullRange)
        tagger.enumerateTags(
            in: fullRange,
            unit: .word,
            scheme: .lemma,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, tokenRange in
            let matchedText = String(text[tokenRange])
            let matchedLemma = tag.map { VocabularyTextPolicy.normalizedVocabularyText($0.rawValue) }
                ?? GermanLemmaResolver.lemma(for: matchedText)
            let occurrence = VocabularyTextOccurrence(
                range: NSRange(tokenRange, in: text),
                matchedText: matchedText
            )
            append(occurrence, for: VocabularyTextPolicy.canonicalVocabularyKey(matchedLemma))
            append(occurrence, for: VocabularyTextPolicy.canonicalVocabularyKey(matchedText))
            return true
        }

        if let lineWrapRegex = try? NSRegularExpression(
            pattern: #"\p{L}[\p{L}\p{M}]*[‐‑‒–—-]\s+\p{L}[\p{L}\p{M}]*"#
        ) {
            let nsText = text as NSString
            for match in lineWrapRegex.matches(
                in: text,
                range: NSRange(location: 0, length: nsText.length)
            ) {
                let rawMatch = nsText.substring(with: match.range)
                let candidates = [
                    VocabularyTextPolicy.normalizedOccurrenceText(rawMatch, matching: "layout"),
                    VocabularyTextPolicy.normalizedOccurrenceText(rawMatch, matching: "layout-word")
                ]
                let occurrence = VocabularyTextOccurrence(range: match.range, matchedText: rawMatch)
                for candidate in candidates {
                    append(
                        occurrence,
                        for: VocabularyTextPolicy.canonicalVocabularyKey(
                            GermanLemmaResolver.lemma(for: candidate)
                        )
                    )
                    append(
                        occurrence,
                        for: VocabularyTextPolicy.canonicalVocabularyKey(candidate)
                    )
                }
            }
        }

        return occurrencesByKey.mapValues { occurrences in
            occurrences.sorted {
                if $0.range.location != $1.range.location {
                    return $0.range.location < $1.range.location
                }
                return $0.range.length < $1.range.length
            }
        }
    }
}
