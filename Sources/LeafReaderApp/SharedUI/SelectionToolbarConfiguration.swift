import Foundation
import LeafReaderCore

enum SelectionToolbarContextAction: Equatable {
    case addWord
    case summarize
}

enum SelectionToolbarDisplayMode: Equatable {
    case full(showsSpeak: Bool)
    case offlineWord
    case offlineText
    case needsModelKeyWord
    case needsModelKeyText
}

struct SelectionToolbarConfiguration: Equatable {
    let contextAction: SelectionToolbarContextAction
    let displayMode: SelectionToolbarDisplayMode
    let showsVocabularySaveAction: Bool
    let isVocabularySelectionSaved: Bool

    static func make(
        isVocabularySelection: Bool,
        queryCapability: ReaderQueryCapability,
        shouldShowSpeakAction: Bool,
        isVocabularySelectionSaved: Bool = false
    ) -> SelectionToolbarConfiguration {
        let contextAction: SelectionToolbarContextAction = isVocabularySelection ? .addWord : .summarize
        let displayMode: SelectionToolbarDisplayMode
        switch queryCapability {
        case .modelAvailable:
            displayMode = .full(showsSpeak: shouldShowSpeakAction)
        case .offlineDictionary:
            displayMode = isVocabularySelection ? .offlineWord : .offlineText
        case .needsModelConfiguration:
            displayMode = isVocabularySelection ? .needsModelKeyWord : .needsModelKeyText
        }
        return SelectionToolbarConfiguration(
            contextAction: contextAction,
            displayMode: displayMode,
            showsVocabularySaveAction: isVocabularySelection,
            isVocabularySelectionSaved: isVocabularySelection && isVocabularySelectionSaved
        )
    }
}
