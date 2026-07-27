import Foundation

package enum ReaderAIContextPolicy {
    package static let summaryContentLimit = 6000
    package static let translationContentLimit = 9000
    package static let questionContentLimit = 5000
    package static let combinedContextSuffixLimit = 6000
    package static let nearbyPageExcerptLimit = 1200
    package static let documentAgentCurrentPageLimit = 3500
    package static let documentAgentNearbyTextLimit = 5000
    package static let evidenceBubbleCount = 4
    package static let evidenceBubbleTextLimit = 500

    package static func prefix(_ text: String, limit: Int) -> String {
        String(text.prefix(limit))
    }

    package static func suffix(_ text: String, limit: Int) -> String {
        String(text.suffix(limit))
    }
}
