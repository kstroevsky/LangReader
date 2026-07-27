import Foundation

package struct ReaderFocusedSelection: Equatable {
    package enum Origin: Equatable {
        case explicitSelection
        case readAloudSegment
    }

    package let origin: Origin
    package let text: String
    package let context: String

    package var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    package static func make(
        explicitSelection: String,
        readAloudSelection: String,
        explicitContext: String,
        readAloudContext: String
    ) -> ReaderFocusedSelection? {
        let explicitText = explicitSelection.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitText.isEmpty {
            return ReaderFocusedSelection(
                origin: .explicitSelection,
                text: explicitText,
                context: explicitContext.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let readAloudText = readAloudSelection.trimmingCharacters(in: .whitespacesAndNewlines)
        if !readAloudText.isEmpty {
            return ReaderFocusedSelection(
                origin: .readAloudSegment,
                text: readAloudText,
                context: readAloudContext.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return nil
    }

    package static func resolve(
        explicitSelection: String,
        readAloudSelection: String,
        contextProvider: ReaderAIContextResolver.ContextProvider
    ) -> ReaderFocusedSelection? {
        ReaderAIContextResolver(
            explicitSelection: explicitSelection,
            readAloudSelection: readAloudSelection
        )
        .focusedSelection(contextProvider: contextProvider)
    }
}
