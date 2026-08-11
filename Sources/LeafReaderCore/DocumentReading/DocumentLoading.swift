import Foundation

package struct WebReadableDocument {
    package let html: String
    package let htmlFileURL: URL?
    package let baseURL: URL
    package let plainText: String
    package let plainTextLoader: (@Sendable () -> String)?
    package let coverImageURL: URL?
    package let tocItems: [ReaderTOCItem]
    package let diagnostics: [String]
    package var loadMeasurements: [DocumentLoadMeasurement] = []
}

package struct DocumentLoadMeasurement: Sendable {
    package let event: PerformanceEvent
    package let milliseconds: Double

    package init(event: PerformanceEvent, milliseconds: Double) {
        self.event = event
        self.milliseconds = milliseconds
    }
}

package struct ReaderTOCItem {
    package let title: String
    package let href: String
    package let level: Int

    package init(title: String, href: String, level: Int) {
        self.title = title
        self.href = href
        self.level = level
    }
}

package struct HTMLBodyFragment {
    package let content: String
    package let bodyClasses: String
    package let bodyAttributes: String
}

/// Hands out compiled regular expressions across threads.
///
/// The dictionary and its lock used to be two separate statics on
/// `WebDocumentLoader`, so nothing but convention stopped a caller from reading
/// one without holding the other. Swift 6 rejects that shape outright — global
/// mutable state has to prove it is safe — and keeping the two together is the
/// proof.
package final class RegexCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: NSRegularExpression] = [:]

    package func regex(for pattern: String) -> NSRegularExpression? {
        lock.lock()
        if let cached = storage[pattern] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        // Compiled outside the lock: it is pure work on a local, and holding the
        // lock across it would queue every miss behind the slowest pattern. Two
        // threads racing on the same pattern each compile one and the later
        // write wins, which costs a duplicate compile and nothing else.
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        lock.lock()
        storage[pattern] = regex
        lock.unlock()
        return regex
    }
}

package enum WebDocumentLoader {
    package static let regexCache = RegexCache()

    package static func load(url: URL) throws -> WebReadableDocument {
        switch ReaderDocumentKind.kind(for: url) {
        case .epub:
            return try loadEPUB(url: url)
        case .docx:
            return try loadDOCX(url: url)
        default:
            throw NSError(domain: "LeafReader", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Unsupported document type"
            ])
        }
    }

}
