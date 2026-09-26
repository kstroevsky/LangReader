import Foundation

package enum GermanLemmaSource: Equatable, Sendable {
    case naturalLanguage
    case deterministicAdjectiveMorphology
}

package typealias VocabularyLemmaResolutionProvider = @Sendable (
    _ surfaceForm: String,
    _ taggedLemma: String?,
    _ language: VocabularyLanguageID
) -> GermanLemmaResolution

/// Distinguishes an actual lemma resolution from retaining the surface as a
/// safe fallback. Callers that still need a String can use `value`, while new
/// policy can avoid treating an unresolved identity as authoritative.
package enum GermanLemmaResolution: Equatable, Sendable {
    case resolved(lemma: String, source: GermanLemmaSource)
    case unresolved(surface: String)

    package var value: String {
        switch self {
        case let .resolved(lemma, _): return lemma
        case let .unresolved(surface): return surface
        }
    }
}

// Despite the "German" name, the resolver and matcher are language-neutral:
// the grouping, line-wrap, and homograph logic are the same everywhere and only
// the tagger's language differs. Callers must pass the resolved domain language
// explicitly; uncertainty is handled by exact-form behavior before reaching
// this language-sensitive API.
package enum GermanLemmaResolver {
    package static func lemma(
        for surfaceForm: String,
        language: VocabularyLanguageID,
        analyzerFactory: VocabularyLinguisticAnalyzerFactory = .exactForm
    ) -> String {
        resolution(
            for: surfaceForm,
            language: language,
            analyzerFactory: analyzerFactory
        ).value
    }

    package static func resolution(
        for surfaceForm: String,
        language: VocabularyLanguageID,
        analyzerFactory: VocabularyLinguisticAnalyzerFactory = .exactForm
    ) -> GermanLemmaResolution {
        let analyzer = analyzerFactory.makeAnalyzer()
        return resolution(for: surfaceForm, analyzer: analyzer, language: language)
    }

    /// - Parameter analyzer: worker-local linguistic analyzer reused across
    ///   calls by document scanners.
    /// - Parameter language: the document's language, used to lemmatize.
    package static func lemma(
        for surfaceForm: String,
        analyzer: any VocabularyLinguisticAnalyzing,
        language: VocabularyLanguageID
    ) -> String {
        resolution(for: surfaceForm, analyzer: analyzer, language: language).value
    }

    package static func resolution(
        for surfaceForm: String,
        analyzer: any VocabularyLinguisticAnalyzing,
        language: VocabularyLanguageID
    ) -> GermanLemmaResolution {
        let word = VocabularyTextPolicy.normalizedVocabularyText(surfaceForm)
        guard VocabularyTextPolicy.isSingleVocabularyWord(word),
              !word.isEmpty else { return .unresolved(surface: word) }

        return resolution(
            for: word,
            taggedLemma: analyzer.isolatedLemma(for: word, language: language),
            language: language,
            isKnownGermanWord: { GermanFrequencyRankTable.shared.rank(for: $0) != nil }
        )
    }

    /// Pure decision seam used to test unavailable and identity Apple lemmas
    /// without depending on the host macOS model.
    package static func resolution(
        for surfaceForm: String,
        taggedLemma: String?,
        language: VocabularyLanguageID
    ) -> GermanLemmaResolution {
        resolution(
            for: surfaceForm,
            taggedLemma: taggedLemma,
            language: language,
            isKnownGermanWord: { GermanFrequencyRankTable.shared.rank(for: $0) != nil }
        )
    }

    package static func resolution(
        for surfaceForm: String,
        taggedLemma: String?,
        language: VocabularyLanguageID,
        isKnownGermanWord: (String) -> Bool
    ) -> GermanLemmaResolution {
        let word = VocabularyTextPolicy.normalizedVocabularyText(surfaceForm)
        guard VocabularyTextPolicy.isSingleVocabularyWord(word), !word.isEmpty else {
            return .unresolved(surface: word)
        }

        if let taggedLemma {
            let lemma = VocabularyTextPolicy.normalizedVocabularyText(taggedLemma)
            if VocabularyTextPolicy.isSingleVocabularyWord(lemma),
               VocabularyTextPolicy.canonicalVocabularyKey(lemma)
                   != VocabularyTextPolicy.canonicalVocabularyKey(word) {
                return .resolved(lemma: lemma, source: .naturalLanguage)
            }
        }

        if language == .german,
           let lemma = deterministicGermanAdjectiveLemma(
               for: word,
               isKnownGermanWord: isKnownGermanWord
           ) {
            return .resolved(lemma: lemma, source: .deterministicAdjectiveMorphology)
        }
        return .unresolved(surface: word)
    }

    package static func groupingKey(
        word: String,
        lemma: String? = nil,
        language: VocabularyLanguageID,
        analyzerFactory: VocabularyLinguisticAnalyzerFactory = .exactForm
    ) -> String {
        let trimmedLemma = lemma?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmedLemma.flatMap { value in
            value.isEmpty ? nil : value
        } ?? self.lemma(
            for: word,
            language: language,
            analyzerFactory: analyzerFactory
        )
        return VocabularyTextPolicy.canonicalVocabularyKey(resolved)
    }

    /// Conservative fallback for the productive German `-haft` adjective class.
    /// The inflectional ending is removed only when the resulting base is present
    /// in the bundled German corpus lexicon. `-schaft` nouns and bare `Haft` are
    /// excluded; both otherwise mimic the same suffix mechanically.
    private static func deterministicGermanAdjectiveLemma(
        for word: String,
        isKnownGermanWord: (String) -> Bool
    ) -> String? {
        let key = VocabularyTextPolicy.canonicalVocabularyKey(word)
        let endings = ["em", "en", "er", "es", "e"]
        guard let ending = endings.first(where: { key.hasSuffix($0) && key.count > $0.count }) else {
            return nil
        }
        let candidate = String(key.dropLast(ending.count))
        guard candidate.hasSuffix("haft"),
              candidate != "haft",
              !candidate.hasSuffix("schaft"),
              isKnownGermanWord(candidate) else {
            return nil
        }
        return candidate
    }
}

package enum GermanLemmaOccurrenceMatcher {
    package static let naturalLanguageResolutionProvider: VocabularyLemmaResolutionProvider = {
        surfaceForm, taggedLemma, language in
        GermanLemmaResolver.resolution(
            for: surfaceForm,
            taggedLemma: taggedLemma,
            language: language
        )
    }

    /// The parallel scanner writes each page exactly once. Keeping that write
    /// behind a small Sendable owner avoids passing an inout buffer into a
    /// Swift 6 concurrent closure while preserving page-order results.
    private final class ResultsBuffer: @unchecked Sendable {
        private var values: [[VocabularyTextOccurrence]]
        private let lock = NSLock()

        init(count: Int) {
            values = [[VocabularyTextOccurrence]](repeating: [], count: count)
        }

        func store(_ value: [VocabularyTextOccurrence], at index: Int) {
            lock.lock()
            values[index] = value
            lock.unlock()
        }

        func snapshot() -> [[VocabularyTextOccurrence]] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }

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
        language: VocabularyLanguageID,
        analyzerFactory: VocabularyLinguisticAnalyzerFactory = .exactForm,
        resolutionProvider: @escaping VocabularyLemmaResolutionProvider = naturalLanguageResolutionProvider
    ) -> [[VocabularyTextOccurrence]] {
        guard !texts.isEmpty else { return [] }
        let compiled = VocabularyOccurrenceMatcher.compile(query: selectedForm)

        let results = ResultsBuffer(count: texts.count)
        guard texts.count > 1 else {
            results.store(matches(
                lemma: rawLemma,
                selectedForm: selectedForm,
                in: texts[0],
                compiledQuery: compiled,
                analyzer: analyzerFactory.makeAnalyzer(),
                language: language,
                resolutionProvider: resolutionProvider
            ), at: 0)
            return results.snapshot()
        }

        // Stripe the pages across workers rather than dispatching one job per
        // page: each worker then builds a single analyzer and reuses it, and
        // striping keeps the load even when page lengths vary widely.
        let availableWorkers = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
        let workerCount = min(texts.count, min(4, availableWorkers))
        DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
            let analyzer = analyzerFactory.makeAnalyzer()
            var lemmaMemo: [String: GermanLemmaResolution] = [:]
            var index = worker
            while index < texts.count {
                results.store(matches(
                    lemma: rawLemma,
                    selectedForm: selectedForm,
                    in: texts[index],
                    compiledQuery: compiled,
                    analyzer: analyzer,
                    lemmaMemo: &lemmaMemo,
                    language: language,
                    resolutionProvider: resolutionProvider
                ), at: index)
                index += workerCount
            }
        }
        return results.snapshot()
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
        language: VocabularyLanguageID,
        analyzerFactory: VocabularyLinguisticAnalyzerFactory = .exactForm,
        resolutionProvider: @escaping VocabularyLemmaResolutionProvider = naturalLanguageResolutionProvider
    ) -> Bool {
        let key = VocabularyTextPolicy.canonicalVocabularyKey(groupLemma)
        let surfaceKey = VocabularyTextPolicy.canonicalVocabularyKey(surfaceForm)
        guard !key.isEmpty, !surfaceKey.isEmpty, !context.isEmpty else { return false }
        return matches(
            lemmasByKey: [key: groupLemma],
            in: context,
            language: language,
            analyzerFactory: analyzerFactory,
            resolutionProvider: resolutionProvider
        )[key]?.contains {
            VocabularyTextPolicy.canonicalVocabularyKey($0.matchedText) == surfaceKey
        } ?? false
    }

    package static func matches(
        lemma rawLemma: String,
        selectedForm: String,
        in text: String,
        language: VocabularyLanguageID,
        analyzerFactory: VocabularyLinguisticAnalyzerFactory = .exactForm,
        resolutionProvider: @escaping VocabularyLemmaResolutionProvider = naturalLanguageResolutionProvider
    ) -> [VocabularyTextOccurrence] {
        matches(
            lemma: rawLemma,
            selectedForm: selectedForm,
            in: text,
            compiledQuery: VocabularyOccurrenceMatcher.compile(query: selectedForm),
            analyzer: analyzerFactory.makeAnalyzer(),
            language: language,
            resolutionProvider: resolutionProvider
        )
    }

    private static func matches(
        lemma rawLemma: String,
        selectedForm: String,
        in text: String,
        compiledQuery: VocabularyOccurrenceMatcher.CompiledQuery?,
        analyzer: any VocabularyLinguisticAnalyzing,
        language: VocabularyLanguageID,
        resolutionProvider: @escaping VocabularyLemmaResolutionProvider
    ) -> [VocabularyTextOccurrence] {
        var memo: [String: GermanLemmaResolution] = [:]
        return matches(
            lemma: rawLemma,
            selectedForm: selectedForm,
            in: text,
            compiledQuery: compiledQuery,
            analyzer: analyzer,
            lemmaMemo: &memo,
            language: language,
            resolutionProvider: resolutionProvider
        )
    }

    /// - Parameters:
    ///   - compiledQuery: patterns compiled once by the caller and reused
    ///     across texts.
    ///   - analyzer: reused across texts by a worker and never shared between
    ///     concurrent workers.
    ///   - lemmaMemo: isolated fallback resolutions cached per worker. Identity
    ///     and unavailable lemmas remain explicitly unresolved.
    private static func matches(
        lemma rawLemma: String,
        selectedForm: String,
        in text: String,
        compiledQuery: VocabularyOccurrenceMatcher.CompiledQuery?,
        analyzer: any VocabularyLinguisticAnalyzing,
        lemmaMemo: inout [String: GermanLemmaResolution],
        language: VocabularyLanguageID,
        resolutionProvider: @escaping VocabularyLemmaResolutionProvider
    ) -> [VocabularyTextOccurrence] {
        let lemma = VocabularyTextPolicy.normalizedVocabularyText(rawLemma)
        let selected = VocabularyTextPolicy.normalizedVocabularyText(selectedForm)
        guard VocabularyTextPolicy.isSingleVocabularyWord(lemma),
              VocabularyTextPolicy.isSingleVocabularyWord(selected),
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

        for token in analyzer.tokenEvidence(in: text, language: language) {
            let range = token.range
            if lineWrapSpans.contains(where: { NSIntersectionRange(range, $0).length > 0 }) {
                continue
            }
            guard let tokenRange = Range(range, in: text) else { continue }
            let matchedText = String(text[tokenRange])
            let resolution = tokenResolution(
                surfaceForm: matchedText,
                taggedLemma: token.taggedLemma,
                language: language,
                analyzer: analyzer,
                lemmaMemo: &lemmaMemo,
                resolutionProvider: resolutionProvider
            )
            // Match by lemma, or by a surface that IS the base form spelled
            // identically. The surface test is case-sensitive on purpose: the
            // capitalized noun "Folgen" (lemma "Folge") must not be swept into
            // the verb group "folgen" just because the two fold to one key.
            let matchedLemmaKey = resolvedLemmaKey(resolution)
            guard VocabularyTextPolicy.surfaceMatchesLemmaExactly(matchedText, lemma)
                    || matchedLemmaKey == lemmaKey else { continue }

            let rangeKey = "\(range.location):\(range.length)"
            guard seenRanges.insert(rangeKey).inserted else { continue }
            occurrences.append(VocabularyTextOccurrence(range: range, matchedText: matchedText))
        }

        for match in lineWrapMatches {
            let rawMatch = nsText.substring(with: match.range)
            let normalizedMatch = VocabularyTextPolicy.normalizedOccurrenceText(
                rawMatch,
                matching: selected
            )
            let resolution = isolatedResolution(
                surfaceForm: normalizedMatch,
                language: language,
                analyzer: analyzer,
                resolutionProvider: resolutionProvider
            )
            let rangeKey = "\(match.range.location):\(match.range.length)"
            guard (VocabularyTextPolicy.surfaceMatchesLemmaExactly(normalizedMatch, lemma)
                    || resolvedLemmaKey(resolution) == lemmaKey),
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

    package static func matches(
        lemmasByKey: [String: String],
        in text: String,
        language: VocabularyLanguageID,
        analyzerFactory: VocabularyLinguisticAnalyzerFactory = .exactForm,
        resolutionProvider: @escaping VocabularyLemmaResolutionProvider = naturalLanguageResolutionProvider
    ) -> [String: [VocabularyTextOccurrence]] {
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

        let analyzer = analyzerFactory.makeAnalyzer()
        var lemmaMemo: [String: GermanLemmaResolution] = [:]
        for token in analyzer.tokenEvidence(in: text, language: language) {
            let range = token.range
            if lineWrapSpans.contains(where: { NSIntersectionRange(range, $0).length > 0 }) {
                continue
            }
            guard let tokenRange = Range(range, in: text) else { continue }
            let matchedText = String(text[tokenRange])
            let resolution = tokenResolution(
                surfaceForm: matchedText,
                taggedLemma: token.taggedLemma,
                language: language,
                analyzer: analyzer,
                lemmaMemo: &lemmaMemo,
                resolutionProvider: resolutionProvider
            )
            let occurrence = VocabularyTextOccurrence(
                range: range,
                matchedText: matchedText
            )
            if let key = resolvedLemmaKey(resolution) {
                append(occurrence, for: key)
            }
            appendBySurface(occurrence, surface: matchedText)
        }

        for match in lineWrapMatches {
            let rawMatch = nsText.substring(with: match.range)
            let candidates = [
                VocabularyTextPolicy.normalizedOccurrenceText(rawMatch, matching: "layout"),
                VocabularyTextPolicy.normalizedOccurrenceText(rawMatch, matching: "layout-word")
            ]
            let occurrence = VocabularyTextOccurrence(range: match.range, matchedText: rawMatch)
            for candidate in candidates {
                let resolution = isolatedResolution(
                    surfaceForm: candidate,
                    language: language,
                    analyzer: analyzer,
                    resolutionProvider: resolutionProvider
                )
                if let key = resolvedLemmaKey(resolution) {
                    append(occurrence, for: key)
                }
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

    private static func resolvedLemmaKey(_ resolution: GermanLemmaResolution) -> String? {
        guard case let .resolved(lemma, _) = resolution else { return nil }
        return VocabularyTextPolicy.canonicalVocabularyKey(lemma)
    }

    private static func tokenResolution(
        surfaceForm: String,
        taggedLemma: String?,
        language: VocabularyLanguageID,
        analyzer: any VocabularyLinguisticAnalyzing,
        lemmaMemo: inout [String: GermanLemmaResolution],
        resolutionProvider: VocabularyLemmaResolutionProvider
    ) -> GermanLemmaResolution {
        let contextual = resolutionProvider(surfaceForm, taggedLemma, language)
        if case .resolved = contextual { return contextual }
        if let cached = lemmaMemo[surfaceForm] { return cached }
        let fallback = isolatedResolution(
            surfaceForm: surfaceForm,
            language: language,
            analyzer: analyzer,
            resolutionProvider: resolutionProvider
        )
        lemmaMemo[surfaceForm] = fallback
        return fallback
    }

    private static func isolatedResolution(
        surfaceForm: String,
        language: VocabularyLanguageID,
        analyzer: any VocabularyLinguisticAnalyzing,
        resolutionProvider: VocabularyLemmaResolutionProvider
    ) -> GermanLemmaResolution {
        let word = VocabularyTextPolicy.normalizedVocabularyText(surfaceForm)
        guard VocabularyTextPolicy.isSingleVocabularyWord(word), !word.isEmpty else {
            return .unresolved(surface: word)
        }
        return resolutionProvider(
            word,
            analyzer.isolatedLemma(for: word, language: language),
            language
        )
    }
}
