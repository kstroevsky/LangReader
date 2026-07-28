import Foundation
import LeafReaderCore

package struct ReadingNote: Codable, Identifiable {
    package let id: String
    package let documentID: String
    package let documentTitle: String
    package let documentKind: String
    package let quote: String
    package var markdown: String
    package let locator: Locator
    package let createdAt: Date
    package var updatedAt: Date
    package var isFavorite: Bool = false

    package init(
        id: String,
        documentID: String,
        documentTitle: String,
        documentKind: String,
        quote: String,
        markdown: String,
        locator: Locator,
        createdAt: Date,
        updatedAt: Date,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.documentID = documentID
        self.documentTitle = documentTitle
        self.documentKind = documentKind
        self.quote = quote
        self.markdown = markdown
        self.locator = locator
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
    }

    package struct Locator: Codable {
        package var pdfFragments: [PDFFragment]?
        package var webAnchor: WebAnchor?

        package init(pdfFragments: [PDFFragment]? = nil, webAnchor: WebAnchor? = nil) {
            self.pdfFragments = pdfFragments
            self.webAnchor = webAnchor
        }
    }

    package struct PDFFragment: Codable {
        package let pageIndex: Int
        package let bounds: StoredPDFWordRect

        package init(pageIndex: Int, bounds: StoredPDFWordRect) {
            self.pageIndex = pageIndex
            self.bounds = bounds
        }
    }

    package struct WebAnchor: Codable {
        package let selectedText: String
        package let context: String
        package let occurrenceIndex: Int?
        package let scrollProgress: Double

        package init(selectedText: String, context: String, occurrenceIndex: Int?, scrollProgress: Double) {
            self.selectedText = selectedText
            self.context = context
            self.occurrenceIndex = occurrenceIndex
            self.scrollProgress = scrollProgress
        }
    }
}

extension ReadingNote {
    package var displayTitle: String {
        ReadingNoteTextPolicy.displayTitle(markdown: markdown, quote: quote)
            ?? AppText.localized("未命名笔记", "Untitled Note")
    }
}

extension Sequence where Element == ReadingNote {
    package func sortedForReadingNoteList() -> [ReadingNote] {
        sorted {
            if $0.isFavorite != $1.isFavorite {
                return $0.isFavorite && !$1.isFavorite
            }
            if $0.createdAt == $1.createdAt {
                return $0.id < $1.id
            }
            return $0.createdAt < $1.createdAt
        }
    }

    package func sortedByCreatedAt() -> [ReadingNote] {
        sorted {
            if $0.createdAt == $1.createdAt {
                return $0.id < $1.id
            }
            return $0.createdAt < $1.createdAt
        }
    }
}
