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

package struct VocabularyMorphologicalAnalysisRequest: Sendable {
    package let surface: String
    package let lemma: String
    package let languageCode: String
    package let context: String
    package let contextFingerprint: String
    package let appleHypotheses: [String: Double]

    package init(
        surface: String,
        lemma: String,
        languageCode: String,
        context: String,
        contextFingerprint: String,
        appleHypotheses: [String: Double]
    ) {
        self.surface = surface
        self.lemma = lemma
        self.languageCode = languageCode
        self.context = context
        self.contextFingerprint = contextFingerprint
        self.appleHypotheses = appleHypotheses
    }
}

package typealias VocabularyMorphologicalAnalysisProvider =
    @Sendable (VocabularyMorphologicalAnalysisRequest) -> [VocabularyMorphologicalAnalysis]

package struct VocabularyDocumentLemmaSummary: Codable, Equatable, Sendable {
    package let canonicalKey: String
    package let lemmaKey: String
    package let displayLemma: String
    package let lexicalItemID: VocabularyLexicalItemID?
    package let partOfSpeech: VocabularyPartOfSpeech
    package let anchorID: VocabularyLexicalAnchorID?
    package let resolutionState: VocabularyLexicalResolutionState
    package let assessmentPolicy: VocabularyAssessmentIdentityPolicy
    package let reconciliationDiagnostics: VocabularyLexicalResolutionDiagnostics?
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
        anchorID: VocabularyLexicalAnchorID? = nil,
        resolutionState: VocabularyLexicalResolutionState? = nil,
        assessmentPolicy: VocabularyAssessmentIdentityPolicy? = nil,
        reconciliationDiagnostics: VocabularyLexicalResolutionDiagnostics? = nil,
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
        self.anchorID = anchorID
        self.resolutionState = resolutionState ?? (lexicalItemID == nil ? .unresolved : .resolvedSingle)
        self.assessmentPolicy = assessmentPolicy ?? (lexicalItemID == nil ? .directEvidenceOnly : .fullInference)
        self.reconciliationDiagnostics = reconciliationDiagnostics
        self.observedForms = observedForms
        self.occurrenceCount = occurrenceCount
        self.representativeRange = representativeRange
        self.isConfidentName = isConfidentName
    }
}

/// The production confidence boundary for lexical-class hypotheses. Offline
/// POS fixtures call this same owner instead of reproducing its thresholds.
package enum VocabularyPartOfSpeechConfidencePolicy {
    package static let minimumLeadingProbability = 0.65
    package static let minimumMargin = 0.20

    package static func classify(hypotheses: [String: Double]) -> VocabularyPartOfSpeech {
        analyses(hypotheses: hypotheses, lemma: "").first {
            $0.confidence.isUsable
        }?.partOfSpeech ?? .unknown
    }

    package static func analyses(
        hypotheses: [String: Double],
        lemma: String
    ) -> [VocabularyMorphologicalAnalysis] {
        let ordered = hypotheses
            .filter { $0.value.isFinite && $0.value >= 0 }
            .sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                return $0.key < $1.key
            }
        guard let leading = ordered.first else {
            return [VocabularyMorphologicalAnalysis(
                lemma: lemma,
                partOfSpeech: .unknown,
                source: .appleNaturalLanguage,
                confidence: .unavailable
            )]
        }
        let usable = leading.value >= minimumLeadingProbability
            && leading.value - (ordered.dropFirst().first?.value ?? 0) >= minimumMargin
        return ordered.prefix(2).enumerated().map { index, hypothesis in
            VocabularyMorphologicalAnalysis(
                lemma: lemma,
                partOfSpeech: partOfSpeech(for: hypothesis.key),
                source: .appleNaturalLanguage,
                rawScore: hypothesis.value,
                confidence: index == 0 && usable ? .usable : .insufficient
            )
        }
    }

    private static func partOfSpeech(for rawTag: String) -> VocabularyPartOfSpeech {
        switch NLTag(rawValue: rawTag) {
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
        case .otherWord: return .unknown
        default: return .other
        }
    }
}

package enum VocabularyPartOfSpeechReconciliationPolicy {
    /// Returns the sole confident POS for each lemma. Unknown occurrences may
    /// join only that one class; multiple confident classes remain split.
    package static func soleConfidentPartByLemma(
        _ items: [VocabularyLexicalItemID]
    ) -> [String: VocabularyPartOfSpeech] {
        Dictionary(grouping: items.filter { $0.partOfSpeech != .unknown }, by: \.lemma)
            .compactMapValues { values in
                let parts = Set(values.map(\.partOfSpeech))
                return parts.count == 1 ? parts.first : nil
            }
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
        let dehyphenatedResolution: GermanLemmaResolution
        let hyphenatedResolution: GermanLemmaResolution
    }

    private struct Page: Sendable {
        let text: String
        let occurrencesByLemmaKey: [String: [VocabularyTextOccurrence]]
        let occurrencesByExactSurface: [String: [VocabularyTextOccurrence]]
        let evidence: [PageOccurrenceEvidence]
        let lineWraps: [LineWrap]
    }

    private struct PageOccurrenceEvidence: Sendable {
        let occurrence: VocabularyTextOccurrence
        let anchor: VocabularyLexicalAnchorID
        let displayLemma: String
        let surface: String
        let analyses: [VocabularyMorphologicalAnalysis]
        let legacyPartOfSpeech: VocabularyPartOfSpeech
        let contextFingerprint: String
        let isConfidentName: Bool
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
        resolutionProvider: @escaping VocabularyLemmaResolutionProvider = GermanLemmaOccurrenceMatcher.naturalLanguageResolutionProvider,
        analysisProvider: @escaping VocabularyMorphologicalAnalysisProvider = {
            VocabularyPartOfSpeechConfidencePolicy.analyses(
                hypotheses: $0.appleHypotheses,
                lemma: $0.lemma
            )
        },
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
            var lemmaMemo: [String: GermanLemmaResolution] = [:]
            var remainingIndex = worker
            while remainingIndex < remainingPageIndexes.count, !isCancelled() {
                let pageIndex = remainingPageIndexes[remainingIndex]
                buffer.store(Self.buildPage(
                    text: texts[pageIndex],
                    language: language,
                    tagger: tagger,
                    nameTagger: nameTagger,
                    fallbackTagger: fallbackTagger,
                    lemmaMemo: &lemmaMemo,
                    resolutionProvider: resolutionProvider,
                    analysisProvider: analysisProvider
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
        struct Entry {
            let sourceKey: String
            let item: VocabularyLexicalItemID
            let evidence: PageOccurrenceEvidence
            let sourceRange: VocabularyDocumentSourceRange
        }

        struct Aggregate {
            var displayLemma: String
            var forms: [String: (surface: String, count: Int)]
            var count: Int
            var nameCount: Int
            var representativeRange: VocabularyDocumentSourceRange
        }

        let entries = pages.enumerated().flatMap { unitIndex, page in
            page.evidence.map { evidence -> Entry in
                let item = VocabularyLexicalItemID(
                    language: languageCode,
                    lemma: evidence.displayLemma,
                    partOfSpeech: evidence.legacyPartOfSpeech
                )
                let sourceKey = evidence.anchor.resolvedLemma == nil
                    ? Self.exactSurfaceLexicalKey(
                        languageCode: languageCode,
                        surface: evidence.surface,
                        partOfSpeech: evidence.legacyPartOfSpeech
                    )
                    : item.canonicalKey
                return Entry(
                    sourceKey: sourceKey,
                    item: item,
                    evidence: evidence,
                    sourceRange: VocabularyDocumentSourceRange(
                        unitIndex: unitIndex,
                        utf16Location: evidence.occurrence.range.location,
                        utf16Length: evidence.occurrence.range.length
                    )
                )
            }
        }
        let lexicalItems = entries.map(\.item)
        var lexicalItemByKey: [String: VocabularyLexicalItemID] = [:]
        for entry in entries {
            lexicalItemByKey[entry.sourceKey] = lexicalItemByKey[entry.sourceKey] ?? entry.item
        }
        let soleConfidentPartByLemma = VocabularyPartOfSpeechReconciliationPolicy
            .soleConfidentPartByLemma(lexicalItems)
        var resolvedKeyByKey: [String: String] = [:]

        // Preserve the existing safe base-form repair in the legacy shadow
        // projection while keeping case-sensitive German homographs separate.
        var resolvedKeysByExactLemma: [String: Set<String>] = [:]
        for entry in entries where !entry.sourceKey.hasPrefix("exact|") {
            resolvedKeysByExactLemma[
                Self.exactSurfaceKey(entry.evidence.displayLemma),
                default: []
            ].insert(entry.sourceKey)
        }
        for entry in entries where entry.sourceKey.hasPrefix("exact|") {
            guard let candidates = resolvedKeysByExactLemma[
                Self.exactSurfaceKey(entry.evidence.displayLemma)
            ] else { continue }
            let compatible = candidates.filter { candidateKey in
                guard let candidate = lexicalItemByKey[candidateKey] else { return false }
                return entry.item.partOfSpeech == .unknown
                    || candidate.partOfSpeech == .unknown
                    || entry.item.partOfSpeech == candidate.partOfSpeech
            }
            if compatible.count == 1, let candidate = compatible.first {
                resolvedKeyByKey[entry.sourceKey] = candidate
            }
        }
        for item in lexicalItems where item.partOfSpeech == .unknown {
            guard let partOfSpeech = soleConfidentPartByLemma[item.lemma] else { continue }
            let sourceKey = item.canonicalKey
            guard resolvedKeyByKey[sourceKey] == nil else { continue }
            resolvedKeyByKey[sourceKey] = VocabularyLexicalItemID(
                language: item.language,
                lemma: item.lemma,
                partOfSpeech: partOfSpeech
            ).canonicalKey
        }

        var aggregateByKey: [String: Aggregate] = [:]
        for entry in entries {
            let key = resolvedKeyByKey[entry.sourceKey] ?? entry.sourceKey
            guard !key.isEmpty else { continue }
            var aggregate = aggregateByKey[key] ?? Aggregate(
                displayLemma: entry.evidence.displayLemma,
                forms: [:],
                count: 0,
                nameCount: 0,
                representativeRange: entry.sourceRange
            )
            aggregate.count += 1
            if entry.evidence.isConfidentName { aggregate.nameCount += 1 }
            let surfaceKey = Self.exactSurfaceKey(entry.evidence.surface)
            let existing = aggregate.forms[surfaceKey]
            aggregate.forms[surfaceKey] = (
                existing?.surface ?? entry.evidence.surface,
                (existing?.count ?? 0) + 1
            )
            aggregateByKey[key] = aggregate
        }

        return aggregateByKey.map { key, aggregate in
            let lexicalItemID = lexicalItemByKey[key]
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

    /// Evidence-aware v4 projection. It remains a separate projection while the
    /// ADR is in shadow rollout and production activation is gated by validation.
    package func lexicalSummaries(
        reconciler: VocabularyLexicalReconciler = VocabularyLexicalReconciler()
    ) -> [VocabularyDocumentLemmaSummary] {
        struct OccurrenceRecord {
            let analysis: VocabularyOccurrenceAnalysis
            let displayLemma: String
            let isConfidentName: Bool
        }

        var records: [OccurrenceRecord] = []
        records.reserveCapacity(pages.reduce(0) { $0 + $1.evidence.count })
        for (unitIndex, page) in pages.enumerated() {
            for evidence in page.evidence {
                let sourceRange = VocabularyDocumentSourceRange(
                    unitIndex: unitIndex,
                    utf16Location: evidence.occurrence.range.location,
                    utf16Length: evidence.occurrence.range.length
                )
                records.append(OccurrenceRecord(
                    analysis: VocabularyOccurrenceAnalysis(
                        occurrenceID: VocabularyOccurrenceAnalysisID(
                            unitIndex: unitIndex,
                            utf16Location: evidence.occurrence.range.location,
                            utf16Length: evidence.occurrence.range.length
                        ),
                        sourceRange: sourceRange,
                        surface: evidence.surface,
                        anchor: evidence.anchor,
                        analyses: evidence.analyses,
                        contextFingerprint: evidence.contextFingerprint
                    ),
                    displayLemma: evidence.displayLemma,
                    isConfidentName: evidence.isConfidentName
                ))
            }
        }

        // An identity lemma is not trustworthy by itself. If the document also
        // contains a trustworthy resolved lemma, an exact case-sensitive base
        // spelling may join that anchor. This preserves established base-form
        // coverage without merging capitalized German homographs.
        let resolvedAnchors = Set(records.compactMap { record -> VocabularyLexicalAnchorID? in
            record.analysis.anchor.resolvedLemma == nil ? nil : record.analysis.anchor
        })
        records = records.map { record in
            guard case let .exactSurface(surface) = record.analysis.anchor.basis else {
                return record
            }
            let compatible = resolvedAnchors.filter { anchor in
                guard let lemma = anchor.resolvedLemma else { return false }
                return VocabularyTextPolicy.surfaceMatchesLemmaExactly(surface, lemma)
            }
            guard compatible.count == 1, let anchor = compatible.first else { return record }
            return OccurrenceRecord(
                analysis: VocabularyOccurrenceAnalysis(
                    occurrenceID: record.analysis.occurrenceID,
                    sourceRange: record.analysis.sourceRange,
                    surface: record.analysis.surface,
                    anchor: anchor,
                    analyses: record.analysis.analyses,
                    contextFingerprint: record.analysis.contextFingerprint
                ),
                displayLemma: record.displayLemma,
                isConfidentName: record.isConfidentName
            )
        }

        let recordsByID = Dictionary(uniqueKeysWithValues: records.map {
            ($0.analysis.occurrenceID, $0)
        })
        let byAnchor = Dictionary(grouping: records.map(\.analysis), by: \.anchor)
        var summaries: [VocabularyDocumentLemmaSummary] = []

        func appendSummary(
            occurrenceIDs: [VocabularyOccurrenceAnalysisID],
            anchor: VocabularyLexicalAnchorID,
            lexicalItemID: VocabularyLexicalItemID?,
            resolutionState: VocabularyLexicalResolutionState,
            assessmentPolicy: VocabularyAssessmentIdentityPolicy,
            diagnostics: VocabularyLexicalResolutionDiagnostics,
            residual: Bool = false,
            directEvidenceOccurrenceID: VocabularyOccurrenceAnalysisID? = nil
        ) {
            let selected = occurrenceIDs.compactMap { recordsByID[$0] }.sorted {
                if $0.analysis.sourceRange.unitIndex != $1.analysis.sourceRange.unitIndex {
                    return $0.analysis.sourceRange.unitIndex < $1.analysis.sourceRange.unitIndex
                }
                return $0.analysis.sourceRange.utf16Location < $1.analysis.sourceRange.utf16Location
            }
            guard let first = selected.first else { return }
            var formCounts: [String: (surface: String, count: Int)] = [:]
            for record in selected {
                let key = Self.exactSurfaceKey(record.analysis.surface)
                let existing = formCounts[key]
                formCounts[key] = (
                    existing?.surface ?? record.analysis.surface,
                    (existing?.count ?? 0) + 1
                )
            }
            let directEvidenceSuffix = directEvidenceOccurrenceID.map {
                "|direct|\($0.unitIndex):\($0.utf16Location):\($0.utf16Length)"
            } ?? ""
            let canonicalKey = lexicalItemID?.canonicalKey
                ?? anchor.canonicalKey + (residual ? "|residual" : "") + directEvidenceSuffix
            summaries.append(VocabularyDocumentLemmaSummary(
                canonicalKey: canonicalKey,
                lemmaKey: lexicalItemID?.lemma
                    ?? anchor.resolvedLemma
                    ?? VocabularyTextPolicy.canonicalVocabularyKey(first.displayLemma),
                displayLemma: lexicalItemID?.lemma ?? first.displayLemma,
                lexicalItemID: lexicalItemID,
                partOfSpeech: lexicalItemID?.partOfSpeech ?? .unknown,
                anchorID: anchor,
                resolutionState: resolutionState,
                assessmentPolicy: assessmentPolicy,
                reconciliationDiagnostics: diagnostics,
                observedForms: formCounts.values
                    .map {
                        VocabularyDocumentObservedForm(
                            surface: $0.surface,
                            occurrenceCount: $0.count
                        )
                    }
                    .sorted {
                        if $0.occurrenceCount != $1.occurrenceCount {
                            return $0.occurrenceCount > $1.occurrenceCount
                        }
                        return $0.surface.localizedStandardCompare($1.surface) == .orderedAscending
                    },
                occurrenceCount: selected.count,
                representativeRange: first.analysis.sourceRange,
                isConfidentName: selected.allSatisfy(\.isConfidentName)
            ))
        }

        func appendDirectEvidenceSummaries(
            occurrenceIDs: [VocabularyOccurrenceAnalysisID],
            anchor: VocabularyLexicalAnchorID,
            resolutionState: VocabularyLexicalResolutionState,
            diagnostics: VocabularyLexicalResolutionDiagnostics,
            residual: Bool = false
        ) {
            for occurrenceID in occurrenceIDs {
                appendSummary(
                    occurrenceIDs: [occurrenceID],
                    anchor: anchor,
                    lexicalItemID: nil,
                    resolutionState: resolutionState,
                    assessmentPolicy: .directEvidenceOnly,
                    diagnostics: diagnostics,
                    residual: residual,
                    directEvidenceOccurrenceID: occurrenceID
                )
            }
        }

        for anchor in byAnchor.keys.sorted(by: { $0.canonicalKey < $1.canonicalKey }) {
            let occurrences = byAnchor[anchor] ?? []
            let resolution = reconciler.reconcile(anchor: anchor, occurrences: occurrences)
            switch resolution {
            case let .resolvedSingle(group):
                appendSummary(
                    occurrenceIDs: group.assignedOccurrenceIDs,
                    anchor: anchor,
                    lexicalItemID: group.lexicalItemID,
                    resolutionState: .resolvedSingle,
                    assessmentPolicy: .fullInference,
                    diagnostics: group.diagnostics
                )
                appendDirectEvidenceSummaries(
                    occurrenceIDs: group.residualOccurrenceIDs,
                    anchor: anchor,
                    resolutionState: .resolvedSingle,
                    diagnostics: group.diagnostics,
                    residual: true
                )
            case let .resolvedSplit(partition):
                for child in partition.children {
                    appendSummary(
                        occurrenceIDs: child.assignedOccurrenceIDs,
                        anchor: anchor,
                        lexicalItemID: child.lexicalItemID,
                        resolutionState: .resolvedSplit,
                        assessmentPolicy: .fullInference,
                        diagnostics: partition.diagnostics
                    )
                }
                appendDirectEvidenceSummaries(
                    occurrenceIDs: partition.residualOccurrenceIDs,
                    anchor: anchor,
                    resolutionState: .resolvedSplit,
                    diagnostics: partition.diagnostics,
                    residual: true
                )
            case let .ambiguous(group):
                appendDirectEvidenceSummaries(
                    occurrenceIDs: group.occurrenceIDs,
                    anchor: anchor,
                    resolutionState: .ambiguous,
                    diagnostics: group.diagnostics
                )
            case let .unresolved(group):
                appendDirectEvidenceSummaries(
                    occurrenceIDs: group.occurrenceIDs,
                    anchor: anchor,
                    resolutionState: .unresolved,
                    diagnostics: group.diagnostics
                )
            }
        }

        return summaries.sorted {
            if $0.occurrenceCount != $1.occurrenceCount {
                return $0.occurrenceCount > $1.occurrenceCount
            }
            if $0.canonicalKey != $1.canonicalKey { return $0.canonicalKey < $1.canonicalKey }
            if $0.representativeRange.unitIndex != $1.representativeRange.unitIndex {
                return $0.representativeRange.unitIndex < $1.representativeRange.unitIndex
            }
            return $0.representativeRange.utf16Location < $1.representativeRange.utf16Location
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
                let resolution = normalized == lineWrap.hyphenated
                    ? lineWrap.hyphenatedResolution
                    : lineWrap.dehyphenatedResolution
                guard Self.resolvedLemmaKey(resolution) == lemmaKey
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
                for (candidate, resolution) in [
                    (lineWrap.dehyphenated, lineWrap.dehyphenatedResolution),
                    (lineWrap.hyphenated, lineWrap.hyphenatedResolution)
                ] {
                    if let key = Self.resolvedLemmaKey(resolution) {
                        append(lineWrap.occurrence, key: key)
                    }
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
        lemmaMemo: inout [String: GermanLemmaResolution],
        resolutionProvider: VocabularyLemmaResolutionProvider,
        analysisProvider: VocabularyMorphologicalAnalysisProvider
    ) -> Page {
        guard !text.isEmpty else {
            return Page(
                text: text,
                occurrencesByLemmaKey: [:],
                occurrencesByExactSurface: [:],
                evidence: [],
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
        var bySurface: [String: [VocabularyTextOccurrence]] = [:]
        var evidence: [PageOccurrenceEvidence] = []

        // Renderer line wrapping is presentation geometry, not linguistic
        // structure. PDFKit commonly inserts newlines at visual wraps while
        // Web/DOCX extraction uses spaces or paragraph separators. Tag an
        // equal-UTF16-length whitespace-normalized view so those renderer
        // choices cannot change lemmas/POS, then translate ranges back to the
        // untouched source text for selections and highlights.
        let taggingText = linguisticTaggingText(text)
        tagger.string = taggingText
        nameTagger.string = taggingText
        let fullRange = taggingText.startIndex..<taggingText.endIndex
        tagger.setLanguage(language, range: fullRange)
        nameTagger.setLanguage(language, range: fullRange)
        tagger.enumerateTags(
            in: fullRange,
            unit: .word,
            scheme: .lemma,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, tokenRange in
            let range = NSRange(tokenRange, in: taggingText)
            guard let sourceRange = Range(range, in: text) else { return true }
            if lineWrapSpans.contains(where: { NSIntersectionRange(range, $0).length > 0 }) {
                return true
            }
            let surface = String(text[sourceRange])
            if ignoredRanges.contains(where: { NSIntersectionRange(range, $0).length > 0 })
                || isObviousArtifact(surface) {
                return true
            }
            let resolution = tokenResolution(
                surfaceForm: surface,
                taggedLemma: tag?.rawValue,
                language: language,
                fallbackTagger: fallbackTagger,
                lemmaMemo: &lemmaMemo,
                resolutionProvider: resolutionProvider
            )
            let matchedLemma = resolution.value
            let occurrence = VocabularyTextOccurrence(range: range, matchedText: surface)
            let hypotheses = tagger.tagHypotheses(
                at: tokenRange.lowerBound,
                unit: .word,
                scheme: .lexicalClass,
                maximumCount: 2
            ).0
            let context = contextWindow(in: taggingText, range: range)
            let fingerprint = contextFingerprint(context)
            let analyses = analysisProvider(VocabularyMorphologicalAnalysisRequest(
                surface: surface,
                lemma: matchedLemma,
                languageCode: language.rawValue,
                context: context,
                contextFingerprint: fingerprint,
                appleHypotheses: hypotheses
            ))
            let partOfSpeech = analyses.first { $0.confidence.isUsable }?.partOfSpeech ?? .unknown
            let anchor: VocabularyLexicalAnchorID
            if let lemmaKey = resolvedLemmaKey(resolution) {
                byLemma[lemmaKey, default: []].append(occurrence)
                anchor = VocabularyLexicalAnchorID(
                    language: language.rawValue,
                    basis: .resolvedLemma(lemmaKey)
                )
            } else {
                anchor = VocabularyLexicalAnchorID(
                    language: language.rawValue,
                    basis: .exactSurface(surface)
                )
            }
            bySurface[exactSurfaceKey(surface), default: []].append(occurrence)
            let nameTag = nameTagger.tag(
                at: tokenRange.lowerBound,
                unit: .word,
                scheme: .nameType
            ).0
            evidence.append(PageOccurrenceEvidence(
                occurrence: occurrence,
                anchor: anchor,
                displayLemma: matchedLemma,
                surface: surface,
                analyses: analyses,
                legacyPartOfSpeech: partOfSpeech,
                contextFingerprint: fingerprint,
                isConfidentName: nameTag == .personalName
                    || nameTag == .placeName
                    || nameTag == .organizationName
            ))
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
                dehyphenatedResolution: isolatedResolution(
                    surfaceForm: dehyphenated,
                    language: language,
                    tagger: fallbackTagger,
                    resolutionProvider: resolutionProvider
                ),
                hyphenatedResolution: isolatedResolution(
                    surfaceForm: hyphenated,
                    language: language,
                    tagger: fallbackTagger,
                    resolutionProvider: resolutionProvider
                )
            )
        }
        for lineWrap in lineWraps {
            let resolution = lineWrap.dehyphenatedResolution
            let displayLemma = resolution.value
            let anchor: VocabularyLexicalAnchorID
            if let lemmaKey = resolvedLemmaKey(resolution) {
                byLemma[lemmaKey, default: []].append(lineWrap.occurrence)
                anchor = VocabularyLexicalAnchorID(
                    language: language.rawValue,
                    basis: .resolvedLemma(lemmaKey)
                )
            } else {
                anchor = VocabularyLexicalAnchorID(
                    language: language.rawValue,
                    basis: .exactSurface(lineWrap.dehyphenated)
                )
            }
            bySurface[exactSurfaceKey(lineWrap.dehyphenated), default: []].append(lineWrap.occurrence)
            evidence.append(PageOccurrenceEvidence(
                occurrence: lineWrap.occurrence,
                anchor: anchor,
                displayLemma: displayLemma,
                surface: lineWrap.dehyphenated,
                analyses: [VocabularyMorphologicalAnalysis(
                    lemma: displayLemma,
                    partOfSpeech: .unknown,
                    source: .appleNaturalLanguage,
                    confidence: .unavailable
                )],
                legacyPartOfSpeech: .unknown,
                contextFingerprint: contextFingerprint(
                    contextWindow(in: taggingText, range: lineWrap.occurrence.range)
                ),
                isConfidentName: false
            ))
        }
        return Page(
            text: text,
            occurrencesByLemmaKey: byLemma,
            occurrencesByExactSurface: bySurface,
            evidence: evidence,
            lineWraps: lineWraps
        )
    }

    private static func resolvedLemmaKey(_ resolution: GermanLemmaResolution) -> String? {
        guard case let .resolved(lemma, _) = resolution else { return nil }
        return VocabularyTextPolicy.canonicalVocabularyKey(lemma)
    }

    private static func exactSurfaceLexicalKey(
        languageCode: String,
        surface: String,
        partOfSpeech: VocabularyPartOfSpeech
    ) -> String {
        let exact = exactSurfaceKey(surface)
            .replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "|", with: "%7C")
        return ["exact", languageCode.lowercased(), exact, partOfSpeech.rawValue]
            .joined(separator: "|")
    }

    private static func contextWindow(in text: String, range: NSRange) -> String {
        let nsText = text as NSString
        let radius = 64
        let lower = max(0, range.location - radius)
        let upper = min(nsText.length, range.location + range.length + radius)
        guard upper > lower else { return "" }
        let window = nsText.substring(with: NSRange(location: lower, length: upper - lower))
        return window
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    private static func contextFingerprint(_ normalizedContext: String) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in normalizedContext.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }

    private static func tokenResolution(
        surfaceForm: String,
        taggedLemma: String?,
        language: NLLanguage,
        fallbackTagger: NLTagger,
        lemmaMemo: inout [String: GermanLemmaResolution],
        resolutionProvider: VocabularyLemmaResolutionProvider
    ) -> GermanLemmaResolution {
        let contextual = resolutionProvider(surfaceForm, taggedLemma, language)
        if case .resolved = contextual { return contextual }
        if let cached = lemmaMemo[surfaceForm] { return cached }
        let fallback = isolatedResolution(
            surfaceForm: surfaceForm,
            language: language,
            tagger: fallbackTagger,
            resolutionProvider: resolutionProvider
        )
        lemmaMemo[surfaceForm] = fallback
        return fallback
    }

    private static func isolatedResolution(
        surfaceForm: String,
        language: NLLanguage,
        tagger: NLTagger,
        resolutionProvider: VocabularyLemmaResolutionProvider
    ) -> GermanLemmaResolution {
        let word = VocabularyTextPolicy.normalizedVocabularyText(surfaceForm)
        guard VocabularyTextPolicy.isSingleEnglishWord(word), !word.isEmpty else {
            return .unresolved(surface: word)
        }
        tagger.string = word
        let range = word.startIndex..<word.endIndex
        tagger.setLanguage(language, range: range)
        let taggedLemma = tagger.tag(
            at: word.startIndex,
            unit: .word,
            scheme: .lemma
        ).0?.rawValue
        return resolutionProvider(word, taggedLemma, language)
    }

    private static func exactSurfaceKey(_ value: String) -> String {
        VocabularyTextPolicy.normalizedVocabularyText(value).precomposedStringWithCanonicalMapping
    }

    private static func linguisticTaggingText(_ text: String) -> String {
        let space = Unicode.Scalar(32)!
        return String(String.UnicodeScalarView(text.unicodeScalars.map {
            CharacterSet.whitespacesAndNewlines.contains($0) ? space : $0
        }))
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
