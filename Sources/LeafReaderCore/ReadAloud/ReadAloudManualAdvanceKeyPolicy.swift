import Foundation

package enum ReadAloudManualAdvanceKeyPolicy {
    package enum Action: Equatable {
        case next
        case replayCurrent
        case replayPrevious
    }

    package static func action(for key: String?) -> Action? {
        guard let key else { return nil }
        switch key {
        case "\\", "、":
            return .next
        case "]", "】":
            return .replayCurrent
        case "[", "【":
            return .replayPrevious
        default:
            return nil
        }
    }

    package static func accepts(_ key: String?) -> Bool {
        action(for: key) != nil
    }
}
