import Foundation
import LeafReaderCore

enum VocabularyRecordProvider {
    /// Resolves the grammatical label for one observed surface form.
    ///
    /// Injected so this provider stays independent of the dictionary cache:
    /// the app supplies the cache-backed resolver, while tests and any caller
    /// without the SQLite stack get the offline rules by default.
    typealias FormLabelResolver = @Sendable (_ surfaceForm: String, _ lemma: String, _ context: String) -> GermanFormLabel?

    static let offlineFormLabelResolver: FormLabelResolver = { surfaceForm, lemma, context in
        GermanFormLabeler.label(surfaceForm: surfaceForm, lemma: lemma, context: context)
    }

    static func records(
        documentKind: ReaderDocumentKind,
        pdfRecords: [StoredPDFWordRecord],
        webRecords: [StoredWebWordRecord],
        pdfContext: (StoredPDFWordRecord) -> String,
        formLabel: FormLabelResolver = offlineFormLabelResolver
    ) -> [VocabularyExportRecord] {
        // Labeling a form runs NaturalLanguage tagging and, for cached words, a
        // SQLite lookup — a few milliseconds each. A document with 100+ saved
        // instances of the same word would pay that per instance, yet every
        // record of a given surface form collapses to a single labeled
        // `VocabularyForm` in `aggregate`/`VocabularyFormMerger`, which keeps the
        // first non-nil label. Memoizing the first non-nil label per
        // (surface, lemma) is therefore output-identical while cutting the work
        // to one call per distinct form. Nil is not cached, so a later occurrence
        // whose context finally resolves a label still gets its chance — matching
        // the merger's "first non-nil wins" exactly.
        var labelMemo: [String: GermanFormLabel] = [:]
        func memoizedLabel(surface: String, lemma: String, context: String) -> GermanFormLabel? {
            let key = VocabularyTextPolicy.canonicalVocabularyKey(surface)
                + "\u{1}" + VocabularyTextPolicy.canonicalVocabularyKey(lemma)
            if let hit = labelMemo[key] { return hit }
            let resolved = formLabel(surface, lemma, context)
            if let resolved { labelMemo[key] = resolved }
            return resolved
        }

        let records: [VocabularyExportRecord]
        if documentKind == .pdf {
            records = pdfRecords
                .map {
                    let location = AppText.localized("第 \($0.pageIndex + 1) 页", "p. \($0.pageIndex + 1)")
                    let context = pdfContext($0)
                    return VocabularyExportRecord(
                        ids: [$0.id],
                        word: $0.word,
                        lemma: $0.lemma,
                        forms: [
                            VocabularyForm(
                                surface: $0.occurrenceSurfaceForm,
                                label: memoizedLabel(
                                    surface: $0.occurrenceSurfaceForm,
                                    lemma: $0.lemma ?? $0.word,
                                    context: context
                                )
                            )
                        ],
                        answer: $0.answer,
                        dictionaryTags: $0.dictionaryTags,
                        dictionaryFrequency: $0.dictionaryFrequency,
                        location: location,
                        context: context,
                        createdAt: $0.createdAt,
                        srs: $0.srs ?? VocabularySRSState.initial(createdAt: $0.createdAt),
                        occurrences: [
                            VocabularyOccurrence(
                                id: $0.id,
                                pageIndex: $0.pageIndex,
                                bounds: $0.bounds,
                                location: location,
                                surfaceForm: $0.occurrenceSurfaceForm,
                                context: context,
                                createdAt: $0.createdAt
                            )
                        ]
                    )
                }
        } else {
            records = webRecords
                .map {
                    let location = AppText.localized(
                        "进度 \(Int(($0.scrollProgress * 100).rounded()))%",
                        "\(Int(($0.scrollProgress * 100).rounded()))%"
                    )
                    return VocabularyExportRecord(
                        ids: [$0.id],
                        word: $0.word,
                        answer: $0.answer,
                        dictionaryTags: $0.dictionaryTags,
                        dictionaryFrequency: $0.dictionaryFrequency,
                        location: location,
                        context: $0.context,
                        createdAt: $0.createdAt,
                        srs: $0.srs ?? VocabularySRSState.initial(createdAt: $0.createdAt),
                        occurrences: [
                            VocabularyOccurrence(
                                id: $0.id,
                                pageIndex: nil,
                                bounds: nil,
                                location: location,
                                context: $0.context,
                                createdAt: $0.createdAt
                            )
                        ]
                    )
                }
        }
        return aggregate(records)
    }

    static func aggregate(_ records: [VocabularyExportRecord]) -> [VocabularyExportRecord] {
        var order: [String] = []
        var grouped: [String: [VocabularyExportRecord]] = [:]
        for record in records.sorted(by: { $0.createdAt < $1.createdAt }) {
            let key = VocabularyTextPolicy.canonicalVocabularyKey(record.lemma ?? record.word)
            guard !key.isEmpty else { continue }
            if grouped[key] == nil {
                order.append(key)
                grouped[key] = []
            }
            grouped[key]?.append(record)
        }

        return order.compactMap { key in
            guard let group = grouped[key], let first = group.first else { return nil }
            var seenLocations = Set<String>()
            let locations = group.map(\.location).filter { location in
                guard !seenLocations.contains(location) else { return false }
                seenLocations.insert(location)
                return true
            }
            let locationText: String
            if group.count > 1 {
                locationText = AppText.localized(
                    "出现 \(group.count) 次：\(locations.prefix(6).joined(separator: "、"))",
                    "\(group.count) occurrences: \(locations.prefix(6).joined(separator: ", "))"
                )
            } else {
                locationText = first.location
            }
            let context = group
                .map(\.context)
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
            let forms = VocabularyFormMerger.merged(group.flatMap(\.forms))
            let answer = group
                .map(\.answer)
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? first.answer
            let dictionaryTags = group
                .compactMap(\.dictionaryTags)
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let dictionaryFrequency = group
                .compactMap(\.dictionaryFrequency)
                .min()
            let occurrences = group
                .flatMap(\.occurrences)
                .sorted(by: occurrenceSort)
            return VocabularyExportRecord(
                ids: group.flatMap(\.ids),
                word: displayWord(first.word),
                lemma: first.lemma,
                forms: forms,
                answer: answer,
                dictionaryTags: dictionaryTags,
                dictionaryFrequency: dictionaryFrequency,
                location: locationText,
                context: context,
                createdAt: first.createdAt,
                srs: group.map(\.srs).min { $0.dueDate < $1.dueDate } ?? first.srs,
                occurrences: occurrences
            )
        }
    }

    static func displayWord(_ word: String) -> String {
        VocabularyTextPolicy.normalizedVocabularyText(word)
    }

    private static func occurrenceSort(_ lhs: VocabularyOccurrence, _ rhs: VocabularyOccurrence) -> Bool {
        switch (lhs.pageIndex, rhs.pageIndex) {
        case let (left?, right?) where left != right:
            return left < right
        case let (left?, right?) where left == right:
            let leftBounds = lhs.bounds?.cgRect ?? .zero
            let rightBounds = rhs.bounds?.cgRect ?? .zero
            if leftBounds.maxY != rightBounds.maxY {
                return leftBounds.maxY > rightBounds.maxY
            }
            return leftBounds.minX < rightBounds.minX
        default:
            return lhs.createdAt < rhs.createdAt
        }
    }
}
