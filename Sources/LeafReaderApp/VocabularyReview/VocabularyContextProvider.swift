import Foundation
import PDFKit

enum VocabularyContextProvider {
    private static let selectionInset = CGSize(width: -120, height: -36)
    private static let fallbackInset = CGSize(width: -80, height: -24)

    static func pdfContext(for record: StoredPDFWordRecord, document: PDFDocument?) -> String {
        if let replacement = replacementPDFContextIfNeeded(for: record, document: document) {
            return replacement
        }
        if let context = VocabularyExporter.nonEmptyText(record.context) {
            return context
        }
        guard let page = document?.page(at: record.pageIndex) else { return "" }
        let pageText = page.string ?? ""
        if let context = exactPDFContext(for: record, page: page, pageText: pageText) {
            return context
        }
        let selectedText = VocabularyExporter.trimmed(record.occurrenceSurfaceForm)
        if let context = ReaderAIContextBuilder.selectedTextContext(selectedText: selectedText, sourceText: pageText, radius: 24) {
            return context
        }
        let expandedBounds = record.bounds.cgRect.insetBy(
            dx: selectionInset.width,
            dy: selectionInset.height
        )
        if let nearbyText = page.selection(for: expandedBounds)?.string,
           let context = ReaderAIContextBuilder.selectedTextContext(selectedText: selectedText, sourceText: nearbyText, radius: 24) {
            return context
        }
        let fallbackBounds = record.bounds.cgRect.insetBy(
            dx: fallbackInset.width,
            dy: fallbackInset.height
        )
        return ReaderAIContextBuilder.normalizeWhitespace(page.selection(for: fallbackBounds)?.string ?? "")
    }

    static func replacementPDFContextIfNeeded(
        for record: StoredPDFWordRecord,
        document: PDFDocument?
    ) -> String? {
        let storedContext = VocabularyExporter.nonEmptyText(record.context)
        if let storedContext,
           storedContext.count <= 360,
           !VocabularyOccurrenceMatcher.matches(query: record.occurrenceSurfaceForm, in: storedContext).isEmpty,
           !appearsToBeginWithPDFHeading(storedContext) {
            return nil
        }
        guard let page = document?.page(at: record.pageIndex) else { return nil }
        return exactPDFContext(for: record, page: page, pageText: page.string ?? "")
    }

    private static func exactPDFContext(
        for record: StoredPDFWordRecord,
        page: PDFPage,
        pageText: String
    ) -> String? {
        guard !pageText.isEmpty else { return nil }
        let targetBounds = record.bounds.cgRect
        let nearest = VocabularyOccurrenceMatcher.matches(query: record.occurrenceSurfaceForm, in: pageText)
            .compactMap { occurrence -> (VocabularyTextOccurrence, CGFloat)? in
                guard let selection = page.selection(for: occurrence.range) else { return nil }
                let bounds = selection.bounds(for: page)
                guard bounds.width > 0, bounds.height > 0 else { return nil }
                let dx = bounds.midX - targetBounds.midX
                let dy = bounds.midY - targetBounds.midY
                let expandedTarget = targetBounds.insetBy(dx: -6, dy: -6)
                let intersectionPenalty: CGFloat = expandedTarget.intersects(bounds) ? 0 : 1_000_000
                return (occurrence, intersectionPenalty + (dx * dx) + (dy * dy))
            }
            .min { $0.1 < $1.1 }?
            .0
        guard let nearest else { return nil }
        return ReaderAIContextBuilder.selectedTextContext(
            occurrenceRange: nearest.range,
            sourceText: pageText,
            radius: 24
        )
    }

    private static func appearsToBeginWithPDFHeading(_ context: String) -> Bool {
        guard let first = context.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return false
        }
        return !first.isLetter
            && !first.isNumber
            && !#""“”‘’'`„«"#.contains(first)
    }
}
