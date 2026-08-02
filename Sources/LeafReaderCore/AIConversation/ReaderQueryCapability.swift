import Foundation

package struct ReaderCapabilityState: Equatable {
    package let isOnline: Bool
    package let hasModelAPIKey: Bool
    package let isLocalDictionaryInstalled: Bool

    package init(isOnline: Bool, hasModelAPIKey: Bool, isLocalDictionaryInstalled: Bool) {
        self.isOnline = isOnline
        self.hasModelAPIKey = hasModelAPIKey
        self.isLocalDictionaryInstalled = isLocalDictionaryInstalled
    }

    package var queryCapability: ReaderQueryCapability {
        ReaderQueryCapability.current(
            isOnline: isOnline,
            hasModelAPIKey: hasModelAPIKey
        )
    }

    package static func make(
        isOnline: Bool,
        hasModelAPIKey: Bool,
        isLocalDictionaryInstalled: Bool
    ) -> ReaderCapabilityState {
        ReaderCapabilityState(
            isOnline: isOnline,
            hasModelAPIKey: hasModelAPIKey,
            isLocalDictionaryInstalled: isLocalDictionaryInstalled
        )
    }
}

package enum ReaderQueryCapability: Equatable {
    case modelAvailable
    case offlineDictionary
    case needsModelConfiguration

    package static func current(
        isOnline: Bool,
        hasModelAPIKey: Bool
    ) -> ReaderQueryCapability {
        guard isOnline else { return .offlineDictionary }
        guard hasModelAPIKey else { return .needsModelConfiguration }
        return .modelAvailable
    }
}
