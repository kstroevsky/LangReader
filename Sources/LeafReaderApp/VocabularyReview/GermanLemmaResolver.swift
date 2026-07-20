import Foundation
import NaturalLanguage

enum GermanLemmaResolver {
    static func lemma(for surfaceForm: String) -> String {
        lemma(for: surfaceForm, tagger: NLTagger(tagSchemes: [.lemma]))
    }

    /// - Parameter tagger: reused across calls by the occurrence scanner.
    ///   Building an `NLTagger` per word costs ~0.23 ms, which dominated
    ///   document scans because a fifth of all tokens fall back to this path.
    ///   Assigning `string` resets the tagger, so one instance serves many
    ///   words, but it must not be shared across threads or reentered from
    ///   inside its own `enumerateTags` callback.
    static func lemma(for surfaceForm: String, tagger: NLTagger) -> String {
        let word = VocabularyTextPolicy.normalizedVocabularyText(surfaceForm)
        guard VocabularyTextPolicy.isSingleEnglishWord(word),
              !word.isEmpty else { return word }

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
    /// Compiled once and shared: this pattern never varies, but the matcher is
    /// called once per page, so building it per call cost a regex compilation
    /// for every page of the document.
    static let lineWrapRegex = try? NSRegularExpression(
        pattern: #"\p{L}[\p{L}\p{M}]*[‐‑‒–—-]\s+\p{L}[\p{L}\p{M}]*"#
    )

    /// Scans many texts for one lemma, in parallel.
    ///
    /// Saving a word searches every page of the document, and lemma tagging
    /// dominates that cost — measured at 6.6 s across a 207-page book. The work
    /// is per-page independent, so it parallelises exactly; results are written
    /// to distinct indices and returned in page order, making the output
    /// identical to scanning sequentially.
    static func matches(
        lemma rawLemma: String,
        selectedForm: String,
        inTexts texts: [String]
    ) -> [[VocabularyTextOccurrence]] {
        guard !texts.isEmpty else { return [] }
        let compiled = VocabularyOccurrenceMatcher.compile(query: selectedForm)

        var results = [[VocabularyTextOccurrence]](repeating: [], count: texts.count)
        guard texts.count > 1 else {
            results[0] = matches(
                lemma: rawLemma,
                selectedForm: selectedForm,
                in: texts[0],
                compiledQuery: compiled,
                tagger: NLTagger(tagSchemes: [.lemma])
            )
            return results
        }

        // Stripe the pages across workers rather than dispatching one job per
        // page: each worker then builds a single tagger and reuses it, and
        // striping keeps the load even when page lengths vary widely.
        let workerCount = min(texts.count, max(1, ProcessInfo.processInfo.activeProcessorCount))
        results.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
                let tagger = NLTagger(tagSchemes: [.lemma])
                // A second tagger: the first is mid-enumeration when the
                // fallback fires and cannot be reentered.
                let fallbackTagger = NLTagger(tagSchemes: [.lemma])
                var lemmaMemo: [String: String] = [:]
                var index = worker
                while index < texts.count {
                    buffer[index] = matches(
                        lemma: rawLemma,
                        selectedForm: selectedForm,
                        in: texts[index],
                        compiledQuery: compiled,
                        tagger: tagger,
                        fallbackTagger: fallbackTagger,
                        lemmaMemo: &lemmaMemo
                    )
                    index += workerCount
                }
            }
        }
        return results
    }

    static func matches(lemma rawLemma: String, selectedForm: String, in text: String) -> [VocabularyTextOccurrence] {
        matches(
            lemma: rawLemma,
            selectedForm: selectedForm,
            in: text,
            compiledQuery: VocabularyOccurrenceMatcher.compile(query: selectedForm),
            tagger: NLTagger(tagSchemes: [.lemma])
        )
    }

    private static func matches(
        lemma rawLemma: String,
        selectedForm: String,
        in text: String,
        compiledQuery: VocabularyOccurrenceMatcher.CompiledQuery?,
        tagger: NLTagger
    ) -> [VocabularyTextOccurrence] {
        var memo: [String: String] = [:]
        return matches(
            lemma: rawLemma,
            selectedForm: selectedForm,
            in: text,
            compiledQuery: compiledQuery,
            tagger: tagger,
            fallbackTagger: NLTagger(tagSchemes: [.lemma]),
            lemmaMemo: &memo
        )
    }

    /// - Parameters:
    ///   - compiledQuery: patterns compiled once by the caller and reused
    ///     across texts.
    ///   - tagger: reused across texts by a worker. Assigning `string` resets
    ///     it, so one instance can serve many pages, but it must never be
    ///     shared between concurrent workers.
    ///   - fallbackTagger: used only for tokens the primary tagger returns no
    ///     lemma for, which cannot reuse `tagger` mid-enumeration.
    ///   - lemmaMemo: fallback results cached per worker. Roughly a fifth of
    ///     tokens take this path and repeat heavily across a document.
    private static func matches(
        lemma rawLemma: String,
        selectedForm: String,
        in text: String,
        compiledQuery: VocabularyOccurrenceMatcher.CompiledQuery?,
        tagger: NLTagger,
        fallbackTagger: NLTagger,
        lemmaMemo: inout [String: String]
    ) -> [VocabularyTextOccurrence] {
        let lemma = VocabularyTextPolicy.normalizedVocabularyText(rawLemma)
        let selected = VocabularyTextPolicy.normalizedVocabularyText(selectedForm)
        guard VocabularyTextPolicy.isSingleEnglishWord(lemma),
              VocabularyTextPolicy.isSingleEnglishWord(selected),
              !text.isEmpty else {
            guard let compiledQuery else { return [] }
            return VocabularyOccurrenceMatcher.matches(compiled: compiledQuery, in: text)
        }

        let lemmaKey = VocabularyTextPolicy.canonicalVocabularyKey(lemma)
        var occurrences = compiledQuery.map {
            VocabularyOccurrenceMatcher.matches(compiled: $0, in: text)
        } ?? []
        var seenRanges = Set(occurrences.map { "\($0.range.location):\($0.range.length)" })

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
            let matchedLemma: String
            if let tag {
                matchedLemma = VocabularyTextPolicy.normalizedVocabularyText(tag.rawValue)
            } else if let cached = lemmaMemo[matchedText] {
                matchedLemma = cached
            } else {
                matchedLemma = GermanLemmaResolver.lemma(for: matchedText, tagger: fallbackTagger)
                lemmaMemo[matchedText] = matchedLemma
            }
            let surfaceKey = VocabularyTextPolicy.canonicalVocabularyKey(matchedText)
            let matchedLemmaKey = VocabularyTextPolicy.canonicalVocabularyKey(matchedLemma)
            guard surfaceKey == lemmaKey || matchedLemmaKey == lemmaKey else { return true }

            let range = NSRange(tokenRange, in: text)
            let rangeKey = "\(range.location):\(range.length)"
            guard seenRanges.insert(rangeKey).inserted else { return true }
            occurrences.append(VocabularyTextOccurrence(range: range, matchedText: matchedText))
            return true
        }

        if let lineWrapRegex {
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

        if let lineWrapRegex {
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
