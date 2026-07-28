import Foundation
import NaturalLanguage
import LeafReaderCore

// Despite the "German" name, the resolver and matcher are language-neutral:
// the grouping, line-wrap, and homograph logic are the same everywhere and only
// the tagger's language differs. Callers pass an `NLLanguage`, defaulting to
// English; the app always passes the detected document language explicitly.
package enum GermanLemmaResolver {
    package static func lemma(for surfaceForm: String, language: NLLanguage = .english) -> String {
        lemma(for: surfaceForm, tagger: NLTagger(tagSchemes: [.lemma]), language: language)
    }

    /// - Parameter tagger: reused across calls by the occurrence scanner.
    ///   Building an `NLTagger` per word costs ~0.23 ms, which dominated
    ///   document scans because a fifth of all tokens fall back to this path.
    ///   Assigning `string` resets the tagger, so one instance serves many
    ///   words, but it must not be shared across threads or reentered from
    ///   inside its own `enumerateTags` callback.
    /// - Parameter language: the document's language, used to lemmatize.
    package static func lemma(for surfaceForm: String, tagger: NLTagger, language: NLLanguage = .english) -> String {
        let word = VocabularyTextPolicy.normalizedVocabularyText(surfaceForm)
        guard VocabularyTextPolicy.isSingleEnglishWord(word),
              !word.isEmpty else { return word }

        tagger.string = word
        let fullRange = word.startIndex..<word.endIndex
        tagger.setLanguage(language, range: fullRange)
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

    package static func groupingKey(word: String, lemma: String? = nil, language: NLLanguage = .english) -> String {
        let trimmedLemma = lemma?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmedLemma.flatMap { value in
            value.isEmpty ? nil : value
        } ?? self.lemma(for: word, language: language)
        return VocabularyTextPolicy.canonicalVocabularyKey(resolved)
    }
}

package enum GermanLemmaOccurrenceMatcher {
    /// Compiled once and shared: this pattern never varies, but the matcher is
    /// called once per page, so building it per call cost a regex compilation
    /// for every page of the document.
    package static let lineWrapRegex = try? NSRegularExpression(
        pattern: #"\p{L}[\p{L}\p{M}]*[‐‑‒–—-]\s+\p{L}[\p{L}\p{M}]*"#
    )

    /// Scans many texts for one lemma, in parallel.
    ///
    /// Saving a word searches every page of the document, and lemma tagging
    /// dominates that cost — measured at 6.6 s across a 207-page book. The work
    /// is per-page independent, so it parallelises exactly; results are written
    /// to distinct indices and returned in page order, making the output
    /// identical to scanning sequentially.
    package static func matches(
        lemma rawLemma: String,
        selectedForm: String,
        inTexts texts: [String],
        language: NLLanguage = .english
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
                tagger: NLTagger(tagSchemes: [.lemma]),
                language: language
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
                        lemmaMemo: &lemmaMemo,
                        language: language
                    )
                    index += workerCount
                }
            }
        }
        return results
    }

    /// Whether the fixed group scan still assigns `surfaceForm` to the group
    /// identified by `groupLemma` within `context`. Used at load to drop
    /// occurrences the pre-fix recognizer mis-filed: hyphenated line-break
    /// fragments ("folg" out of "Er-\nfolg") and case-folded homographs (the
    /// noun "Folgen", lemma "Folge", swept into the verb group "folgen"). It
    /// asks about *group membership*, not mere findability, so it leaves
    /// same-line compound constituents ("Abteilung" in "IT-Abteilung") intact.
    package static func groupReproducesOccurrence(
        surfaceForm: String,
        groupLemma: String,
        in context: String,
        language: NLLanguage = .english
    ) -> Bool {
        let key = VocabularyTextPolicy.canonicalVocabularyKey(groupLemma)
        let surfaceKey = VocabularyTextPolicy.canonicalVocabularyKey(surfaceForm)
        guard !key.isEmpty, !surfaceKey.isEmpty, !context.isEmpty else { return false }
        return matches(lemmasByKey: [key: groupLemma], in: context, language: language)[key]?.contains {
            VocabularyTextPolicy.canonicalVocabularyKey($0.matchedText) == surfaceKey
        } ?? false
    }

    package static func matches(lemma rawLemma: String, selectedForm: String, in text: String, language: NLLanguage = .english) -> [VocabularyTextOccurrence] {
        matches(
            lemma: rawLemma,
            selectedForm: selectedForm,
            in: text,
            compiledQuery: VocabularyOccurrenceMatcher.compile(query: selectedForm),
            tagger: NLTagger(tagSchemes: [.lemma]),
            language: language
        )
    }

    private static func matches(
        lemma rawLemma: String,
        selectedForm: String,
        in text: String,
        compiledQuery: VocabularyOccurrenceMatcher.CompiledQuery?,
        tagger: NLTagger,
        language: NLLanguage
    ) -> [VocabularyTextOccurrence] {
        var memo: [String: String] = [:]
        return matches(
            lemma: rawLemma,
            selectedForm: selectedForm,
            in: text,
            compiledQuery: compiledQuery,
            tagger: tagger,
            fallbackTagger: NLTagger(tagSchemes: [.lemma]),
            lemmaMemo: &memo,
            language: language
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
        lemmaMemo: inout [String: String],
        language: NLLanguage
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

        // Ranges spanning a hyphenated line break ("Er-\nfolg"). A token that
        // falls inside one is a fragment of a split word, not a word in its own
        // right, so it is matched only via the joined form in the line-wrap pass
        // below — never on its own, which would turn "folg" (the tail of
        // "Erfolg") into a false hit for the lemma "folgen".
        let nsText = text as NSString
        let lineWrapMatches = lineWrapRegex?.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ) ?? []
        let lineWrapSpans = lineWrapMatches.map(\.range)

        tagger.string = text
        let fullRange = text.startIndex..<text.endIndex
        tagger.setLanguage(language, range: fullRange)
        tagger.enumerateTags(
            in: fullRange,
            unit: .word,
            scheme: .lemma,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, tokenRange in
            let range = NSRange(tokenRange, in: text)
            if lineWrapSpans.contains(where: { NSIntersectionRange(range, $0).length > 0 }) {
                return true
            }
            let matchedText = String(text[tokenRange])
            let matchedLemma: String
            if let tag {
                matchedLemma = VocabularyTextPolicy.normalizedVocabularyText(tag.rawValue)
            } else if let cached = lemmaMemo[matchedText] {
                matchedLemma = cached
            } else {
                matchedLemma = GermanLemmaResolver.lemma(for: matchedText, tagger: fallbackTagger, language: language)
                lemmaMemo[matchedText] = matchedLemma
            }
            // Match by lemma, or by a surface that IS the base form spelled
            // identically. The surface test is case-sensitive on purpose: the
            // capitalized noun "Folgen" (lemma "Folge") must not be swept into
            // the verb group "folgen" just because the two fold to one key.
            let matchedLemmaKey = VocabularyTextPolicy.canonicalVocabularyKey(matchedLemma)
            guard VocabularyTextPolicy.surfaceMatchesLemmaExactly(matchedText, lemma)
                    || matchedLemmaKey == lemmaKey else { return true }

            let rangeKey = "\(range.location):\(range.length)"
            guard seenRanges.insert(rangeKey).inserted else { return true }
            occurrences.append(VocabularyTextOccurrence(range: range, matchedText: matchedText))
            return true
        }

        for match in lineWrapMatches {
            let rawMatch = nsText.substring(with: match.range)
            let normalizedMatch = VocabularyTextPolicy.normalizedOccurrenceText(
                rawMatch,
                matching: selected
            )
            let matchedLemmaKey = VocabularyTextPolicy.canonicalVocabularyKey(
                GermanLemmaResolver.lemma(for: normalizedMatch, language: language)
            )
            let rangeKey = "\(match.range.location):\(match.range.length)"
            guard matchedLemmaKey == lemmaKey,
                  seenRanges.insert(rangeKey).inserted else { continue }
            occurrences.append(VocabularyTextOccurrence(range: match.range, matchedText: rawMatch))
        }

        return occurrences.sorted {
            if $0.range.location != $1.range.location {
                return $0.range.location < $1.range.location
            }
            return $0.range.length < $1.range.length
        }
    }

    package static func matches(lemmasByKey: [String: String], in text: String, language: NLLanguage = .english) -> [String: [VocabularyTextOccurrence]] {
        guard !lemmasByKey.isEmpty, !text.isEmpty else { return [:] }
        var occurrencesByKey: [String: [VocabularyTextOccurrence]] = [:]
        var seenRangesByKey: [String: Set<String>] = [:]

        func append(_ occurrence: VocabularyTextOccurrence, for key: String) {
            guard lemmasByKey[key] != nil else { return }
            let rangeKey = "\(occurrence.range.location):\(occurrence.range.length)"
            guard seenRangesByKey[key, default: []].insert(rangeKey).inserted else { return }
            occurrencesByKey[key, default: []].append(occurrence)
        }

        // File an occurrence under a group only when its surface IS that group's
        // base form spelled identically (case-sensitive). This keeps the German
        // noun "Folgen" (lemma "Folge") out of the verb group "folgen", which a
        // case-folded key match would wrongly merge.
        func appendBySurface(_ occurrence: VocabularyTextOccurrence, surface: String) {
            let key = VocabularyTextPolicy.canonicalVocabularyKey(surface)
            guard let groupLemma = lemmasByKey[key],
                  VocabularyTextPolicy.surfaceMatchesLemmaExactly(surface, groupLemma) else { return }
            append(occurrence, for: key)
        }

        // See the sibling matcher: tokens inside a hyphenated line break are
        // fragments of a split word and must be matched only via the joined
        // form in the line-wrap pass below, never on their own.
        let nsText = text as NSString
        let lineWrapMatches = lineWrapRegex?.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ) ?? []
        let lineWrapSpans = lineWrapMatches.map(\.range)

        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        let fullRange = text.startIndex..<text.endIndex
        tagger.setLanguage(language, range: fullRange)
        tagger.enumerateTags(
            in: fullRange,
            unit: .word,
            scheme: .lemma,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, tokenRange in
            let range = NSRange(tokenRange, in: text)
            if lineWrapSpans.contains(where: { NSIntersectionRange(range, $0).length > 0 }) {
                return true
            }
            let matchedText = String(text[tokenRange])
            let matchedLemma = tag.map { VocabularyTextPolicy.normalizedVocabularyText($0.rawValue) }
                ?? GermanLemmaResolver.lemma(for: matchedText, language: language)
            let occurrence = VocabularyTextOccurrence(
                range: range,
                matchedText: matchedText
            )
            append(occurrence, for: VocabularyTextPolicy.canonicalVocabularyKey(matchedLemma))
            appendBySurface(occurrence, surface: matchedText)
            return true
        }

        for match in lineWrapMatches {
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
                        GermanLemmaResolver.lemma(for: candidate, language: language)
                    )
                )
                appendBySurface(occurrence, surface: candidate)
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
