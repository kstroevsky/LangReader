import Foundation
import PDFKit
import LeafReaderCore

private func fail(_ message: String) -> Never {
    fputs("PDFVocabularyDocumentTests failed: \(message)\n", stderr)
    exit(1)
}

@main
struct PDFVocabularyDocumentTestRunner {
    static func main() {
        let paths = Array(CommandLine.arguments.dropFirst())
        guard paths.count == 2 else {
            fail("expected answered and answerless PDF paths")
        }

        for (offset, path) in paths.enumerated() {
            let expectedCount = 2
            guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
                fail("PDFKit could not load \(path)")
            }
            guard document.pageCount == 207 else {
                fail("expected 207 pages in \(path), got \(document.pageCount)")
            }

            var matches: [(pageIndex: Int, occurrence: VocabularyTextOccurrence)] = []
            for pageIndex in 0..<document.pageCount {
                guard let text = document.page(at: pageIndex)?.string else { continue }
                matches.append(contentsOf: VocabularyOccurrenceMatcher.matches(query: "übersende", in: text).map {
                    (pageIndex, $0)
                })
            }

            guard matches.count == expectedCount else {
                fail("expected \(expectedCount) exact übersende occurrence(s) in \(path), got \(matches.count)")
            }
            guard matches.allSatisfy({ $0.pageIndex == 79 }) else {
                fail("all übersende occurrences should be on displayed page 80")
            }
            if offset == 0,
               !matches.contains(where: {
                   $0.occurrence.matchedText.range(of: #"[‐‑‒–—-]\s*"#, options: .regularExpression) != nil
               }) {
                fail("the answered PDF should exercise the über- / sende layout-wrap path")
            }

            for match in matches {
                guard let page = document.page(at: match.pageIndex),
                      let sourceText = page.string,
                      let selection = page.selection(for: match.occurrence.range) else {
                    fail("PDFKit could not reconstruct an occurrence selection")
                }
                guard let anchor = TextQuoteAnchor(
                    unitOrdinal: match.pageIndex,
                    sourceRange: match.occurrence.range,
                    sourceText: sourceText
                ), anchor.exactQuote == match.occurrence.matchedText else {
                    fail("semantic anchor should retain the exact German PDF quote")
                }
                guard anchor.resolvedRange(in: sourceText) == match.occurrence.range else {
                    fail("semantic anchor should resolve the original German PDF occurrence")
                }
                let bounds = selection.bounds(for: page)
                guard bounds.width > 0, bounds.height > 0 else {
                    fail("PDFKit occurrence bounds must be navigable")
                }
                let selectedText = VocabularyTextPolicy.normalizedOccurrenceText(
                    selection.string ?? "",
                    matching: "übersende"
                )
                let selectedKey = VocabularyTextPolicy.canonicalVocabularyKey(selectedText)
                guard selectedKey == VocabularyTextPolicy.canonicalVocabularyKey("übersende") else {
                    fail("PDFKit selection text should retain the German Unicode spelling")
                }
            }
        }

        print("PDFVocabularyDocumentTests passed")
    }
}
