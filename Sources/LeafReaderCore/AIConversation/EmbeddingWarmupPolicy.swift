import Foundation

package struct EmbeddingWarmupPolicy {
    package static let cacheRestoreDelay: TimeInterval = 5.0
    package static let warmupDelay: TimeInterval = 18.0
    package static let idleThreshold: TimeInterval = 4.0

    package static func isReaderIdle(lastInteractionAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastInteractionAt) >= idleThreshold
    }
}
