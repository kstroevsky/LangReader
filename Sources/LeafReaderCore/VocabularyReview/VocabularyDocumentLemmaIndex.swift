import Foundation
import NaturalLanguage

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
        let occurrencesByExactSurface: [String: [VocabularyTextOccurrence]]
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
            let tagger = NLTagger(tagSchemes: [.lemma])
            let fallbackTagger = NLTagger(tagSchemes: [.lemma])
            var lemmaMemo: [String: String] = [:]
            var remainingIndex = worker
            while remainingIndex < remainingPageIndexes.count, !isCancelled() {
                let pageIndex = remainingPageIndexes[remainingIndex]
                buffer.store(Self.buildPage(
                    text: texts[pageIndex],
                    language: language,
                    tagger: tagger,
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

    package func matches(lemma rawLemma: String, selectedForm: String) -> [[VocabularyTextOccurrence]] {
        let lemma = VocabularyTextPolicy.normalizedVocabularyText(rawLemma)
        let selected = VocabularyTextPolicy.normalizedVocabularyText(selectedForm)
        guard VocabularyTextPolicy.isSingleEnglishWord(lemma),
              VocabularyTextPolicy.isSingleEnglishWord(selected) else {
            return pages.map { VocabularyOccurrenceMatcher.matches(query: selectedForm, in: $0.text) }
        }

        let lemmaKey = VocabularyTextPolicy.canonicalVocabularyKey(lemma)
        let exactLemmaKey = Self.exactSurfaceKey(lemma)
        let compiled = VocabularyOccurrenceMatcher.compile(query: selected)
        return pages.map { page in
            var occurrences = compiled.map { VocabularyOccurrenceMatcher.matches(compiled: $0, in: page.text) } ?? []
            var seenRanges = Set(occurrences.map(Self.rangeKey))

            func append(_ occurrence: VocabularyTextOccurrence) {
                guard seenRanges.insert(Self.rangeKey(occurrence)).inserted else { return }
                occurrences.append(occurrence)
            }

            page.occurrencesByLemmaKey[lemmaKey]?.forEach(append)
            page.occurrencesByExactSurface[exactLemmaKey]?.forEach(append)
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
                append(lineWrap.occurrence)
            }
            return Self.sorted(occurrences)
        }
    }

    /// Returns one grouped result dictionary per input page, preserving page
    /// positions for callers that need to create PDF selections afterwards.
    package func matches(lemmasByKey: [String: String]) -> [[String: [VocabularyTextOccurrence]]] {
        guard !lemmasByKey.isEmpty else { return pages.map { _ in [:] } }
        let exactSurfaceByGroupKey = lemmasByKey.mapValues(Self.exactSurfaceKey)
        var groupKeysByExactSurface: [String: [String]] = [:]
        for (groupKey, exactSurface) in exactSurfaceByGroupKey {
            groupKeysByExactSurface[exactSurface, default: []].append(groupKey)
        }
        return pages.map { page in
            var result: [String: [VocabularyTextOccurrence]] = [:]
            var seen: [String: Set<String>] = [:]

            func append(_ occurrence: VocabularyTextOccurrence, key: String) {
                guard lemmasByKey[key] != nil,
                      seen[key, default: []].insert(Self.rangeKey(occurrence)).inserted else { return }
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
            return result.mapValues(Self.sorted)
        }
    }

    private static func buildPage(
        text: String,
        language: NLLanguage,
        tagger: NLTagger,
        fallbackTagger: NLTagger,
        lemmaMemo: inout [String: String]
    ) -> Page {
        guard !text.isEmpty else {
            return Page(text: text, occurrencesByLemmaKey: [:], occurrencesByExactSurface: [:], lineWraps: [])
        }

        let nsText = text as NSString
        let lineWrapMatches = GermanLemmaOccurrenceMatcher.lineWrapRegex?.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ) ?? []
        let lineWrapSpans = lineWrapMatches.map(\.range)
        var byLemma: [String: [VocabularyTextOccurrence]] = [:]
        var bySurface: [String: [VocabularyTextOccurrence]] = [:]

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
            let surface = String(text[tokenRange])
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
            byLemma[VocabularyTextPolicy.canonicalVocabularyKey(matchedLemma), default: []].append(occurrence)
            bySurface[exactSurfaceKey(surface), default: []].append(occurrence)
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
        return Page(
            text: text,
            occurrencesByLemmaKey: byLemma,
            occurrencesByExactSurface: bySurface,
            lineWraps: lineWraps
        )
    }

    private static func exactSurfaceKey(_ value: String) -> String {
        VocabularyTextPolicy.normalizedVocabularyText(value).precomposedStringWithCanonicalMapping
    }

    private static func rangeKey(_ occurrence: VocabularyTextOccurrence) -> String {
        "\(occurrence.range.location):\(occurrence.range.length)"
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
