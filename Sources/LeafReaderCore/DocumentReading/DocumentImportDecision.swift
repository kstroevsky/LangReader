import Foundation

/// Decides whether a Finder drop opens one document or presents the shelf for a batch.
package enum DocumentImportDecision: Equatable {
    case ignore
    case open(URL)
    case showShelf([URL])

    package static func make(urls: [URL]) -> DocumentImportDecision {
        let supported = supportedUniqueURLs(urls)
        guard !supported.isEmpty else { return .ignore }

        let supportedDropCount = urls.filter { ReaderDocumentKind.kind(for: $0) != nil }.count
        if supportedDropCount == 1, supported.count == 1, let url = supported.first {
            return .open(url)
        }
        return .showShelf(supported)
    }

    private static func supportedUniqueURLs(_ urls: [URL]) -> [URL] {
        var supported: [URL] = []
        var seenPaths = Set<String>()
        for url in urls where ReaderDocumentKind.kind(for: url) != nil {
            let fileURL = url.standardizedFileURL
            guard seenPaths.insert(fileURL.path).inserted else { continue }
            supported.append(fileURL)
        }
        return supported
    }
}
