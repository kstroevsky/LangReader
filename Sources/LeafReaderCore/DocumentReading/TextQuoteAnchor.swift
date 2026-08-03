import Foundation

/// Stable text identity for a source occurrence. Geometry may be cached beside
/// it by a renderer, but is not part of the quote's semantic identity.
package struct TextQuoteAnchor: Codable, Equatable, Sendable {
    package static let currentVersion = 1

    package let unitOrdinal: Int
    package let sourceStart: Int
    package let sourceLength: Int
    package let exactQuote: String
    package let prefix: String
    package let suffix: String
    package let version: Int

    package init?(
        unitOrdinal: Int,
        sourceRange: NSRange,
        sourceText: String,
        contextLength: Int = 32,
        version: Int = currentVersion
    ) {
        let source = sourceText as NSString
        guard unitOrdinal >= 0,
              sourceRange.location != NSNotFound,
              sourceRange.location >= 0,
              sourceRange.length > 0,
              NSMaxRange(sourceRange) <= source.length else { return nil }

        let radius = max(0, contextLength)
        let prefixStart = max(0, sourceRange.location - radius)
        let suffixEnd = min(source.length, NSMaxRange(sourceRange) + radius)
        self.unitOrdinal = unitOrdinal
        sourceStart = sourceRange.location
        sourceLength = sourceRange.length
        exactQuote = source.substring(with: sourceRange)
        prefix = source.substring(with: NSRange(
            location: prefixStart,
            length: sourceRange.location - prefixStart
        ))
        suffix = source.substring(with: NSRange(
            location: NSMaxRange(sourceRange),
            length: suffixEnd - NSMaxRange(sourceRange)
        ))
        self.version = version
    }
}
