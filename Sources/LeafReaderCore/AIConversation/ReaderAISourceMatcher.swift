import CoreGraphics
import Foundation
import LeafReaderCore

package struct ReaderAISourceMatcher {
    package static let minimumTextOverlapTokens = 4
    package static let webProgressMatchTolerance = 0.08

    package let currentDocumentKind: ReaderDocumentKind
    package let currentWebProgress: Double
    package let candidates: [AIConversationSourceLocation]

    package init(
        currentDocumentKind: ReaderDocumentKind,
        currentWebProgress: Double,
        candidates: [AIConversationSourceLocation]
    ) {
        self.currentDocumentKind = currentDocumentKind
        self.currentWebProgress = currentWebProgress
        self.candidates = candidates
    }

    package func readAloudSource(
        matching text: String,
        pageIndex: Int?,
        pdfBounds: CGRect?,
        webProgress: Double?
    ) -> AIConversationSourceLocation? {
        let segmentText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segmentText.isEmpty else { return nil }

        if currentDocumentKind == .pdf, let pageIndex {
            return pdfSource(
                in: candidates.filter { $0.kind == .pdfPage && $0.index == pageIndex },
                text: segmentText,
                pdfBounds: pdfBounds
            )
        }

        let webSources = candidates.filter { $0.kind == .webProgress }
        if let source = webSources.first(where: { Self.aiSourceText($0, overlapsReadAloudText: segmentText) }) {
            return source
        }
        return webProgressSource(in: webSources, progress: webProgress)
    }

    private func pdfSource(
        in sources: [AIConversationSourceLocation],
        text: String,
        pdfBounds: CGRect?
    ) -> AIConversationSourceLocation? {
        if let pdfBounds,
           let source = sources.first(where: { Self.pdfBounds(pdfBounds, intersects: $0.pdfBounds) }) {
            return source
        }
        if let source = sources.first(where: { Self.aiSourceText($0, overlapsReadAloudText: text) }) {
            return source
        }
        if sources.count == 1 {
            return sources.first
        }
        return sources.first(where: Self.isPageLevelAISource)
    }

    private func webProgressSource(in sources: [AIConversationSourceLocation], progress: Double?) -> AIConversationSourceLocation? {
        let target = progress ?? currentWebProgress
        let candidates = sources.compactMap { source -> (source: AIConversationSourceLocation, distance: Double)? in
            guard let sourceProgress = source.progress else { return nil }
            return (source, abs(sourceProgress - target))
        }
        guard let closest = candidates.min(by: { $0.distance < $1.distance }),
              closest.distance <= Self.webProgressMatchTolerance else {
            return nil
        }
        return closest.source
    }

    package static func pdfBounds(_ segmentBounds: CGRect, intersects sourceBounds: [StoredPDFWordRect]?) -> Bool {
        guard !segmentBounds.isNull,
              let sourceBounds,
              !sourceBounds.isEmpty else {
            return false
        }
        let paddedSegment = segmentBounds.insetBy(dx: -4, dy: -4)
        return sourceBounds.contains { rect in
            paddedSegment.intersects(rect.cgRect.insetBy(dx: -4, dy: -4))
        }
    }

    package static func aiSourceText(_ source: AIConversationSourceLocation, overlapsReadAloudText text: String) -> Bool {
        guard let selectedText = source.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !selectedText.isEmpty else {
            return false
        }
        let selected = normalizedMatchText(selectedText)
        let spoken = normalizedMatchText(text)
        guard !selected.isEmpty, !spoken.isEmpty else { return false }
        if spoken.contains(selected) || selected.contains(spoken) {
            return true
        }
        let selectedTokens = Set(matchTokens(in: selected))
        let spokenTokens = Set(matchTokens(in: spoken))
        guard !selectedTokens.isEmpty, !spokenTokens.isEmpty else { return false }
        let overlap = selectedTokens.intersection(spokenTokens)
        return overlap.count >= min(minimumTextOverlapTokens, selectedTokens.count, spokenTokens.count)
    }

    package static func linkedWordText(_ word: String, overlapsReadAloudText text: String) -> Bool {
        let wordText = normalizedMatchText(word)
        let spoken = normalizedMatchText(text)
        guard !wordText.isEmpty, !spoken.isEmpty else { return false }
        return spoken.contains(wordText) || wordText.contains(spoken)
    }

    package static func isPageLevelAISource(_ source: AIConversationSourceLocation) -> Bool {
        let selectedText = source.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return selectedText.isEmpty && (source.pdfBounds?.isEmpty ?? true)
    }

    package static func normalizedMatchText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    package static func matchTokens(in text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 }
    }
}
