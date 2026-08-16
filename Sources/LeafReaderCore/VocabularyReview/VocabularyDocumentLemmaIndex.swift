import Foundation
import NaturalLanguage

package struct VocabularyDocumentSourceRange: Codable, Equatable, Sendable {
    package let unitIndex: Int
    package let utf16Location: Int
    package let utf16Length: Int

    package init(unitIndex: Int, utf16Location: Int, utf16Length: Int) {
        self.unitIndex = unitIndex
        self.utf16Location = utf16Location
        self.utf16Length = utf16Length
    }
}

package struct VocabularyDocumentObservedForm: Codable, Equatable, Sendable {
    package let surface: String
    package let occurrenceCount: Int

    package init(surface: String, occurrenceCount: Int) {
        self.surface = surface
        self.occurrenceCount = occurrenceCount
    }
}

package struct VocabularyDocumentLemmaSummary: Codable, Equatable, Sendable {
    package let canonicalKey: String
    package let lemmaKey: String
    package let displayLemma: String
    package let lexicalItemID: VocabularyLexicalItemID?
    package let partOfSpeech: VocabularyPartOfSpeech
    package let observedForms: [VocabularyDocumentObservedForm]
    package let occurrenceCount: Int
    package let representativeRange: VocabularyDocumentSourceRange
    package let isConfidentName: Bool

    package init(
        canonicalKey: String,
        lemmaKey: String? = nil,
        displayLemma: String,
        lexicalItemID: VocabularyLexicalItemID? = nil,
        partOfSpeech: VocabularyPartOfSpeech = .unknown,
        observedForms: [VocabularyDocumentObservedForm],
        occurrenceCount: Int,
        representativeRange: VocabularyDocumentSourceRange,
        isConfidentName: Bool = false
    ) {
        self.canonicalKey = canonicalKey
        self.lemmaKey = lemmaKey ?? VocabularyTextPolicy.canonicalVocabularyKey(displayLemma)
        self.displayLemma = displayLemma
        self.lexicalItemID = lexicalItemID
        self.partOfSpeech = partOfSpeech
        self.observedForms = observedForms
        self.occurrenceCount = occurrenceCount
        self.representativeRange = representativeRange
        self.isConfidentName = isConfidentName
    }
}

/// A small, already-built page slice that can seed a whole-document index.
/// The page mapping is explicit because the slice is ordered for latency (the
/// current page first), not necessarily in document order.
package struct VocabularyDocumentLemmaIndexSeed: Sendable {
    package let pageIndexes: [Int]
    package let index: VocabularyDocumentLemmaIndex

    package init(pageIndexes: [Int], index: VocabularyDocumentLemmaIndex) {
        self.pageIndexes = pageIndexes
        self.index = index
    }
}

/// Produces a deterministic, bounded visible-first page slice. Partial callers
/// must keep the returned count separate from the document page count; this is
/// deliberately a priority plan, not a claim that the document is complete.
package enum VocabularyIndexPriorityPlanner {
    package static func pageIndexes(
        pageCount: Int,
        currentPageIndex: Int?,
        visiblePageIndexes: [Int],
        neighborRadius: Int = 1
    ) -> [Int] {
        guard pageCount > 0 else { return [] }
        var result: [Int] = []
        var seen = Set<Int>()

        func append(_ pageIndex: Int?) {
            guard let pageIndex,
                  pageIndex >= 0,
                  pageIndex < pageCount,
                  seen.insert(pageIndex).inserted else { return }
            result.append(pageIndex)
        }

        append(currentPageIndex)
        visiblePageIndexes.sorted().forEach { append($0) }

        let seeds = result
        if neighborRadius > 0 {
            for distance in 1...neighborRadius {
                for seed in seeds {
                    append(seed - distance)
                    append(seed + distance)
                }
            }
        }
        return result
    }
}

/// A document-scoped, immutable index of word occurrences by lemma.
///
/// Building this once avoids running `NLTagger` over every page each time the
/// user saves a word. Literal matching is still evaluated per query because it
/// also supports phrases and PDF line-break spelling variants, but the costly
/// linguistic pass is reused by every save and backfill.
package final class VocabularyDocumentLemmaIndex: @unchecked Sendable {
    private static let ignoredTextRegexes: [NSRegularExpression] = [
        #"(?i)\b(?:https?://|www\.)[^\s<>{}\[\]]+"#,
        #"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
        #"</?[A-Za-z][^>]{0,512}>"#,
        #"&(?:#\d{1,7}|#x[0-9A-Fa-f]{1,6}|[A-Za-z][A-Za-z0-9]{1,31});"#,
        #"\b[\p{L}\p{M}]+(?:--+|'{2,}|’{2,})[\p{L}\p{M}]+\b"#
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    private struct OccurrenceRangeKey: Hashable {
        let location: Int
        let length: Int

        init(_ occurrence: VocabularyTextOccurrence) {
            location = occurrence.range.location
            length = occurrence.range.length
        }
    }

    private struct LineWrap: Sendable {
        let occurrence: VocabularyTextOccurrence
        let dehyphenated: String
        let hyphenated: String
        let dehyphenatedLemmaKey: String
        let hyphenatedLemmaKey: String
    }

    private struct Page: Sendable {
        let text: String
        let occurrencesByLemmaKey: [String: [VocabularyTextOccurrence]]
        let occurrencesByLexicalKey: [String: [VocabularyTextOccurrence]]
        let occurrencesByExactSurface: [String: [VocabularyTextOccurrence]]
        let displayLemmaByLexicalKey: [String: String]
        let lexicalItemByKey: [String: VocabularyLexicalItemID]
        let formCountsByLexicalKey: [String: [String: Int]]
        let nameOccurrenceCountsByLexicalKey: [String: Int]
        let lineWraps: [LineWrap]
    }

    private final class PageBuffer: @unchecked Sendable {
        private var pages: [Page?]
        private let lock = NSLock()

        init(count: Int) {
            pages = [Page?](repeating: nil, count: count)
        }

        func store(_ page: Page, at index: Int) {
            lock.lock()
            pages[index] = page
            lock.unlock()
        }

        func snapshot() -> [Page]? {
            lock.lock()
            defer { lock.unlock() }
            guard pages.allSatisfy({ $0 != nil }) else { return nil }
            return pages.compactMap { $0 }
        }
    }

    private let pages: [Page]
    private let languageCode: String
    package let reusedPageCount: Int

    /// Builds an index using a deliberately bounded worker pool. Natural
    /// Language tagging is CPU- and memory-heavy; consuming every logical core
    /// made the app compete with PDF rendering and increased peak memory.
    package init?(
        texts: [String],
        language: NLLanguage = .english,
        maximumWorkerCount: Int = 4,
        seed: VocabularyDocumentLemmaIndexSeed? = nil,
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) {
        guard !isCancelled() else { return nil }
        languageCode = language.rawValue
        guard !texts.isEmpty else {
            pages = []
            reusedPageCount = 0
            return
        }

        let buffer = PageBuffer(count: texts.count)
        var reusedIndexes = Set<Int>()
        if let seed,
           seed.index.languageCode == language.rawValue,
           seed.pageIndexes.count == seed.index.pages.count {
            for (sliceIndex, pageIndex) in seed.pageIndexes.enumerated() {
                guard pageIndex >= 0,
                      pageIndex < texts.count,
                      texts[pageIndex] == seed.index.pages[sliceIndex].text,
                      reusedIndexes.insert(pageIndex).inserted else { continue }
                buffer.store(seed.index.pages[sliceIndex], at: pageIndex)
            }
        }
        reusedPageCount = reusedIndexes.count
        let remainingPageIndexes = texts.indices.filter { !reusedIndexes.contains($0) }
        guard !remainingPageIndexes.isEmpty else {
            guard !isCancelled(), let pages = buffer.snapshot() else { return nil }
            self.pages = pages
            return
        }

        let availableWorkers = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
        let workerCount = min(remainingPageIndexes.count, max(1, min(maximumWorkerCount, availableWorkers)))
        DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
            let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
            let nameTagger = NLTagger(tagSchemes: [.nameType])
            let fallbackTagger = NLTagger(tagSchemes: [.lemma])
            var lemmaMemo: [String: String] = [:]
            var remainingIndex = worker
            while remainingIndex < remainingPageIndexes.count, !isCancelled() {
                let pageIndex = remainingPageIndexes[remainingIndex]
                buffer.store(Self.buildPage(
                    text: texts[pageIndex],
                    language: language,
                    tagger: tagger,
                    nameTagger: nameTagger,
                    fallbackTagger: fallbackTagger,
                    lemmaMemo: &lemmaMemo
                ), at: pageIndex)
                remainingIndex += workerCount
            }
        }

        guard !isCancelled(), let pages = buffer.snapshot() else { return nil }
        self.pages = pages
    }

    package var pageCount: Int { pages.count }

    /// Returns the immutable document vocabulary population in deterministic
    /// occurrence-first order. A source range identifies the first observed
    /// occurrence in the corresponding PDF page or Web text unit.
    package func lemmaSummaries() -> [VocabularyDocumentLemmaSummary] {
        struct Aggregate {
            var displayLemma: String
            var forms: [String: (surface: String, count: Int)]
            var count: Int
            var nameCount: Int
            var representativeRange: VocabularyDocumentSourceRange
        }

        let lexicalItems = pages.flatMap { $0.lexicalItemByKey.values }
        let confidentPartsByLemma = Dictionary(grouping: lexicalItems.filter {
            $0.partOfSpeech != .unknown
        }, by: \.lemma).mapValues { Set($0.map(\.partOfSpeech)) }
        var resolvedKeyByKey: [String: String] = [:]
        for item in lexicalItems where item.partOfSpeech == .unknown {
            guard let confidentParts = confidentPartsByLemma[item.lemma], confidentParts.count == 1,
                  let partOfSpeech = confidentParts.first else { continue }
            resolvedKeyByKey[item.canonicalKey] = VocabularyLexicalItemID(
                language: item.language,
                lemma: item.lemma,
                partOfSpeech: partOfSpeech
            ).canonicalKey
        }

        var aggregateByKey: [String: Aggregate] = [:]
        for (unitIndex, page) in pages.enumerated() {
            for (sourceKey, occurrences) in page.occurrencesByLexicalKey {
                let key = resolvedKeyByKey[sourceKey] ?? sourceKey
                guard !key.isEmpty, let first = occurrences.first else { continue }
                let representative = VocabularyDocumentSourceRange(
                    unitIndex: unitIndex,
                    utf16Location: first.range.location,
                    utf16Length: first.range.length
                )
                var aggregate = aggregateByKey[key] ?? Aggregate(
                    displayLemma: page.displayLemmaByLexicalKey[sourceKey] ?? first.matchedText,
                    forms: [:],
                    count: 0,
                    nameCount: 0,
                    representativeRange: representative
                )
                aggregate.count += occurrences.count
                aggregate.nameCount += page.nameOccurrenceCountsByLexicalKey[sourceKey] ?? 0
                for (surface, count) in page.formCountsByLexicalKey[sourceKey] ?? [:] {
                    let surfaceKey = Self.exactSurfaceKey(surface)
                    let existing = aggregate.forms[surfaceKey]
                    aggregate.forms[surfaceKey] = (existing?.surface ?? surface, (existing?.count ?? 0) + count)
                }
                aggregateByKey[key] = aggregate
            }
        }

        return aggregateByKey.map { key, aggregate in
            let lexicalItemID = pages.lazy.compactMap { $0.lexicalItemByKey[key] }.first
            return VocabularyDocumentLemmaSummary(
                canonicalKey: key,
                lemmaKey: lexicalItemID?.lemma,
                displayLemma: aggregate.displayLemma,
                lexicalItemID: lexicalItemID,
                partOfSpeech: lexicalItemID?.partOfSpeech ?? .unknown,
                observedForms: aggregate.forms.values
                    .map { VocabularyDocumentObservedForm(surface: $0.surface, occurrenceCount: $0.count) }
                    .sorted {
                        if $0.occurrenceCount != $1.occurrenceCount { return $0.occurrenceCount > $1.occurrenceCount }
                        return $0.surface.localizedStandardCompare($1.surface) == .orderedAscending
                    },
                occurrenceCount: aggregate.count,
                representativeRange: aggregate.representativeRange,
                isConfidentName: aggregate.nameCount == aggregate.count
            )
        }.sorted {
            if $0.occurrenceCount != $1.occurrenceCount { return $0.occurrenceCount > $1.occurrenceCount }
            if $0.canonicalKey != $1.canonicalKey { return $0.canonicalKey < $1.canonicalKey }
            return $0.representativeRange.unitIndex < $1.representativeRange.unitIndex
        }
    }

    package func matches(lemma rawLemma: String, selectedForm: String) -> [[VocabularyTextOccurrence]] {
        let lemma = VocabularyTextPolicy.normalizedVocabularyText(rawLemma)
        let selected = VocabularyTextPolicy.normalizedVocabularyText(selectedForm)
        guard VocabularyTextPolicy.isSingleEnglishWord(lemma),
              VocabularyTextPolicy.isSingleEnglishWord(selected),
              Self.canUseTokenPostings(selected) else {
            return pages.map { VocabularyOccurrenceMatcher.matches(query: selectedForm, in: $0.text) }
        }

        let lemmaKey = VocabularyTextPolicy.canonicalVocabularyKey(lemma)
        let exactLemmaKey = Self.exactSurfaceKey(lemma)
        let exactSelectedKey = Self.exactSurfaceKey(selected)
        return pages.map { page in
            // Posting lists are already emitted in source order. Merge them
            // directly instead of allocating a string key for every range and
            // sorting the same common-word results again on every save.
            var occurrences = page.occurrencesByLemmaKey[lemmaKey] ?? []
            if let selectedOccurrences = page.occurrencesByExactSurface[exactSelectedKey] {
                occurrences = Self.mergeSortedUnique(occurrences, selectedOccurrences)
            }
            if exactLemmaKey != exactSelectedKey,
               let lemmaOccurrences = page.occurrencesByExactSurface[exactLemmaKey] {
                occurrences = Self.mergeSortedUnique(occurrences, lemmaOccurrences)
            }
            var matchingLineWraps: [VocabularyTextOccurrence] = []
            for lineWrap in page.lineWraps {
                let normalized = VocabularyTextPolicy.normalizedOccurrenceText(
                    lineWrap.occurrence.matchedText,
                    matching: selected
                )
                let matchKey = normalized == lineWrap.hyphenated
                    ? lineWrap.hyphenatedLemmaKey
                    : lineWrap.dehyphenatedLemmaKey
                guard matchKey == lemmaKey
                        || VocabularyTextPolicy.surfaceMatchesLemmaExactly(normalized, lemma) else { continue }
                matchingLineWraps.append(lineWrap.occurrence)
            }
            return Self.mergeSortedUnique(occurrences, matchingLineWraps)
        }
    }

    /// Returns one grouped result dictionary per input page, preserving page
    /// positions for callers that need to create PDF selections afterwards.
    package func matches(lemmasByKey: [String: String]) -> [[String: [VocabularyTextOccurrence]]] {
        matches(lemmasByKey: lemmasByKey, isCancelled: { false }) ?? []
    }

    /// Cancellable form used by document-scoped background restoration. A nil
    /// result is unambiguously incomplete and must never be persisted.
    package func matches(
        lemmasByKey: [String: String],
        isCancelled: () -> Bool
    ) -> [[String: [VocabularyTextOccurrence]]]? {
        guard !isCancelled() else { return nil }
        guard !lemmasByKey.isEmpty else { return pages.map { _ in [:] } }
        let exactSurfaceByGroupKey = lemmasByKey.mapValues(Self.exactSurfaceKey)
        var groupKeysByExactSurface: [String: [String]] = [:]
        for (groupKey, exactSurface) in exactSurfaceByGroupKey {
            groupKeysByExactSurface[exactSurface, default: []].append(groupKey)
        }
        var pageResults: [[String: [VocabularyTextOccurrence]]] = []
        pageResults.reserveCapacity(pages.count)
        for page in pages {
            guard !isCancelled() else { return nil }
            var result: [String: [VocabularyTextOccurrence]] = [:]
            var seen: [String: Set<OccurrenceRangeKey>] = [:]

            func append(_ occurrence: VocabularyTextOccurrence, key: String) {
                guard lemmasByKey[key] != nil,
                      seen[key, default: []].insert(OccurrenceRangeKey(occurrence)).inserted else { return }
                result[key, default: []].append(occurrence)
            }

            if lemmasByKey.count <= page.occurrencesByLemmaKey.count {
                for key in lemmasByKey.keys {
                    page.occurrencesByLemmaKey[key]?.forEach { append($0, key: key) }
                }
            } else {
                for (key, occurrences) in page.occurrencesByLemmaKey where lemmasByKey[key] != nil {
                    occurrences.forEach { append($0, key: key) }
                }
            }

            if groupKeysByExactSurface.count <= page.occurrencesByExactSurface.count {
                for (exactSurface, groupKeys) in groupKeysByExactSurface {
                    guard let occurrences = page.occurrencesByExactSurface[exactSurface] else { continue }
                    for key in groupKeys {
                        occurrences.forEach { append($0, key: key) }
                    }
                }
            } else {
                for (exactSurface, occurrences) in page.occurrencesByExactSurface {
                    guard let groupKeys = groupKeysByExactSurface[exactSurface] else { continue }
                    for key in groupKeys {
                        occurrences.forEach { append($0, key: key) }
                    }
                }
            }
            for lineWrap in page.lineWraps {
                guard !isCancelled() else { return nil }
                for (candidate, key) in [
                    (lineWrap.dehyphenated, lineWrap.dehyphenatedLemmaKey),
                    (lineWrap.hyphenated, lineWrap.hyphenatedLemmaKey)
                ] {
                    append(lineWrap.occurrence, key: key)
                    let surfaceKey = VocabularyTextPolicy.canonicalVocabularyKey(candidate)
                    if let groupLemma = lemmasByKey[surfaceKey],
                       VocabularyTextPolicy.surfaceMatchesLemmaExactly(candidate, groupLemma) {
                        append(lineWrap.occurrence, key: surfaceKey)
                    }
                }
            }
            pageResults.append(result.mapValues(Self.sorted))
        }
        return pageResults
    }

    private static func buildPage(
        text: String,
        language: NLLanguage,
        tagger: NLTagger,
        nameTagger: NLTagger,
        fallbackTagger: NLTagger,
        lemmaMemo: inout [String: String]
    ) -> Page {
        guard !text.isEmpty else {
            return Page(
                text: text,
                occurrencesByLemmaKey: [:],
                occurrencesByLexicalKey: [:],
                occurrencesByExactSurface: [:],
                displayLemmaByLexicalKey: [:],
                lexicalItemByKey: [:],
                formCountsByLexicalKey: [:],
                nameOccurrenceCountsByLexicalKey: [:],
                lineWraps: []
            )
        }

        let nsText = text as NSString
        let ignoredRanges = ignoredTextRegexes.flatMap {
            $0.matches(in: text, range: NSRange(location: 0, length: nsText.length)).map(\.range)
        }
        let lineWrapMatches = (GermanLemmaOccurrenceMatcher.lineWrapRegex?.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ) ?? []).filter { match in
            !ignoredRanges.contains { NSIntersectionRange(match.range, $0).length > 0 }
        }
        let lineWrapSpans = lineWrapMatches.map(\.range)
        var byLemma: [String: [VocabularyTextOccurrence]] = [:]
        var byLexical: [String: [VocabularyTextOccurrence]] = [:]
        var bySurface: [String: [VocabularyTextOccurrence]] = [:]
        var displayLemmaByLexicalKey: [String: String] = [:]
        var lexicalItemByKey: [String: VocabularyLexicalItemID] = [:]
        var formCountsByLexicalKey: [String: [String: Int]] = [:]
        var nameOccurrenceCountsByLexicalKey: [String: Int] = [:]

        tagger.string = text
        nameTagger.string = text
        let fullRange = text.startIndex..<text.endIndex
        tagger.setLanguage(language, range: fullRange)
        nameTagger.setLanguage(language, range: fullRange)
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
            let surface = String(text[tokenRange])
            if ignoredRanges.contains(where: { NSIntersectionRange(range, $0).length > 0 })
                || isObviousArtifact(surface) {
                return true
            }
            let matchedLemma: String
            if let tag {
                matchedLemma = VocabularyTextPolicy.normalizedVocabularyText(tag.rawValue)
            } else if let cached = lemmaMemo[surface] {
                matchedLemma = cached
            } else {
                matchedLemma = GermanLemmaResolver.lemma(for: surface, tagger: fallbackTagger, language: language)
                lemmaMemo[surface] = matchedLemma
            }
            let occurrence = VocabularyTextOccurrence(range: range, matchedText: surface)
            let lemmaKey = VocabularyTextPolicy.canonicalVocabularyKey(matchedLemma)
            let partOfSpeech = confidentPartOfSpeech(tagger: tagger, at: tokenRange.lowerBound)
            let lexicalItemID = VocabularyLexicalItemID(
                language: language.rawValue,
                lemma: matchedLemma,
                partOfSpeech: partOfSpeech
            )
            let lexicalKey = lexicalItemID.canonicalKey
            byLemma[lemmaKey, default: []].append(occurrence)
            byLexical[lexicalKey, default: []].append(occurrence)
            bySurface[exactSurfaceKey(surface), default: []].append(occurrence)
            displayLemmaByLexicalKey[lexicalKey] = displayLemmaByLexicalKey[lexicalKey] ?? matchedLemma
            lexicalItemByKey[lexicalKey] = lexicalItemID
            formCountsByLexicalKey[lexicalKey, default: [:]][surface, default: 0] += 1
            let nameTag = nameTagger.tag(
                at: tokenRange.lowerBound,
                unit: .word,
                scheme: .nameType
            ).0
            if nameTag == .personalName || nameTag == .placeName || nameTag == .organizationName {
                nameOccurrenceCountsByLexicalKey[lexicalKey, default: 0] += 1
            }
            return true
        }

        let lineWraps = lineWrapMatches.map { match -> LineWrap in
            let raw = nsText.substring(with: match.range)
            let dehyphenated = VocabularyTextPolicy.normalizedOccurrenceText(raw, matching: "layout")
            let hyphenated = VocabularyTextPolicy.normalizedOccurrenceText(raw, matching: "layout-word")
            return LineWrap(
                occurrence: VocabularyTextOccurrence(range: match.range, matchedText: raw),
                dehyphenated: dehyphenated,
                hyphenated: hyphenated,
                dehyphenatedLemmaKey: VocabularyTextPolicy.canonicalVocabularyKey(
                    GermanLemmaResolver.lemma(for: dehyphenated, tagger: fallbackTagger, language: language)
                ),
                hyphenatedLemmaKey: VocabularyTextPolicy.canonicalVocabularyKey(
                    GermanLemmaResolver.lemma(for: hyphenated, tagger: fallbackTagger, language: language)
                )
            )
        }
        for lineWrap in lineWraps {
            let lemmaKey = lineWrap.dehyphenatedLemmaKey
            guard !lemmaKey.isEmpty else { continue }
            let displayLemma = GermanLemmaResolver.lemma(
                for: lineWrap.dehyphenated,
                tagger: fallbackTagger,
                language: language
            )
            let lexicalItemID = VocabularyLexicalItemID(
                language: language.rawValue,
                lemma: displayLemma,
                partOfSpeech: .unknown
            )
            let lexicalKey = lexicalItemID.canonicalKey
            byLemma[lemmaKey, default: []].append(lineWrap.occurrence)
            byLexical[lexicalKey, default: []].append(lineWrap.occurrence)
            bySurface[exactSurfaceKey(lineWrap.dehyphenated), default: []].append(lineWrap.occurrence)
            displayLemmaByLexicalKey[lexicalKey] = displayLemmaByLexicalKey[lexicalKey] ?? displayLemma
            lexicalItemByKey[lexicalKey] = lexicalItemID
            formCountsByLexicalKey[lexicalKey, default: [:]][lineWrap.dehyphenated, default: 0] += 1
        }
        return Page(
            text: text,
            occurrencesByLemmaKey: byLemma,
            occurrencesByLexicalKey: byLexical,
            occurrencesByExactSurface: bySurface,
            displayLemmaByLexicalKey: displayLemmaByLexicalKey,
            lexicalItemByKey: lexicalItemByKey,
            formCountsByLexicalKey: formCountsByLexicalKey,
            nameOccurrenceCountsByLexicalKey: nameOccurrenceCountsByLexicalKey,
            lineWraps: lineWraps
        )
    }

    private static func confidentPartOfSpeech(
        tagger: NLTagger,
        at index: String.Index
    ) -> VocabularyPartOfSpeech {
        let hypotheses = tagger.tagHypotheses(
            at: index,
            unit: .word,
            scheme: .lexicalClass,
            maximumCount: 2
        ).0.sorted { $0.value > $1.value }
        guard let leading = hypotheses.first,
              leading.value >= 0.65,
              leading.value - (hypotheses.dropFirst().first?.value ?? 0) >= 0.20 else {
            return .unknown
        }
        switch NLTag(rawValue: leading.key) {
        case .noun: return .noun
        case .verb: return .verb
        case .adjective: return .adjective
        case .adverb: return .adverb
        case .pronoun: return .pronoun
        case .determiner: return .determiner
        case .preposition: return .preposition
        case .conjunction: return .conjunction
        case .interjection: return .interjection
        case .particle: return .particle
        default: return .other
        }
    }

    private static func exactSurfaceKey(_ value: String) -> String {
        VocabularyTextPolicy.normalizedVocabularyText(value).precomposedStringWithCanonicalMapping
    }

    private static func isObviousArtifact(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        if normalized.hasPrefix("-") || normalized.hasSuffix("-")
            || normalized.hasPrefix("'") || normalized.hasSuffix("'")
            || normalized.hasPrefix("’") || normalized.hasSuffix("’")
            || normalized.contains("--") || normalized.contains("''") || normalized.contains("’’") {
            return true
        }
        let letters = normalized.lowercased().filter(\.isLetter)
        return letters.count >= 6 && Set(letters).count == 1
    }

    /// Natural Language can split punctuation-bearing selections such as
    /// `E-Mail` differently from the vocabulary matcher. Keep those on the
    /// exact regex fallback; plain alphabetic tokens are safe posting keys.
    private static func canUseTokenPostings(_ value: String) -> Bool {
        !value.unicodeScalars.isEmpty && value.unicodeScalars.allSatisfy {
            CharacterSet.letters.contains($0) || CharacterSet.nonBaseCharacters.contains($0)
        }
    }

    private static func mergeSortedUnique(
        _ lhs: [VocabularyTextOccurrence],
        _ rhs: [VocabularyTextOccurrence]
    ) -> [VocabularyTextOccurrence] {
        guard !lhs.isEmpty else { return rhs }
        guard !rhs.isEmpty else { return lhs }
        var merged: [VocabularyTextOccurrence] = []
        merged.reserveCapacity(lhs.count + rhs.count)
        var leftIndex = 0
        var rightIndex = 0

        while leftIndex < lhs.count, rightIndex < rhs.count {
            let left = lhs[leftIndex]
            let right = rhs[rightIndex]
            if left.range.location < right.range.location
                || (left.range.location == right.range.location && left.range.length < right.range.length) {
                merged.append(left)
                leftIndex += 1
            } else if right.range.location < left.range.location
                || (right.range.location == left.range.location && right.range.length < left.range.length) {
                merged.append(right)
                rightIndex += 1
            } else {
                merged.append(left)
                leftIndex += 1
                rightIndex += 1
            }
        }
        if leftIndex < lhs.count { merged.append(contentsOf: lhs[leftIndex...]) }
        if rightIndex < rhs.count { merged.append(contentsOf: rhs[rightIndex...]) }
        return merged
    }

    private static func sorted(_ occurrences: [VocabularyTextOccurrence]) -> [VocabularyTextOccurrence] {
        occurrences.sorted {
            if $0.range.location != $1.range.location {
                return $0.range.location < $1.range.location
            }
            return $0.range.length < $1.range.length
        }
    }
}
