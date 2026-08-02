import Foundation

package struct ReaderAIContextResolver {
    package typealias ContextProvider = (String) -> String

    package let explicitSelection: String
    package let readAloudSelection: String

    package init(explicitSelection: String, readAloudSelection: String) {
        self.explicitSelection = explicitSelection
        self.readAloudSelection = readAloudSelection
    }

    package func focusedSelection(contextProvider: ContextProvider) -> ReaderFocusedSelection? {
        if let candidate = focusedCandidate {
            return ReaderFocusedSelection(
                origin: candidate.origin,
                text: candidate.text,
                context: contextProvider(candidate.text).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return nil
    }

    package var preferredSelectionText: String {
        focusedCandidate?.text ?? ""
    }

    private var focusedCandidate: Candidate? {
        let explicitText = trimmed(explicitSelection)
        if !explicitText.isEmpty {
            return Candidate(origin: .explicitSelection, text: explicitText)
        }

        let readAloudText = trimmed(readAloudSelection)
        if !readAloudText.isEmpty {
            return Candidate(origin: .readAloudSegment, text: readAloudText)
        }

        return nil
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Candidate {
        let origin: ReaderFocusedSelection.Origin
        let text: String
    }
}
