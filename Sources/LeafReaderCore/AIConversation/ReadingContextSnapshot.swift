import Foundation

package struct ReadingContextSnapshot {
    package let title: String
    package let documentKind: ReaderDocumentKind
    package let locationLabel: String
    package let visibleText: String
    package let nearbyText: String
    package let focusedSelection: ReaderFocusedSelection?

    package init(
        title: String,
        documentKind: ReaderDocumentKind,
        locationLabel: String,
        visibleText: String,
        nearbyText: String,
        focusedSelection: ReaderFocusedSelection?
    ) {
        self.title = title
        self.documentKind = documentKind
        self.locationLabel = locationLabel
        self.visibleText = visibleText
        self.nearbyText = nearbyText
        self.focusedSelection = focusedSelection
    }

    package init(
        title: String,
        documentKind: ReaderDocumentKind,
        locationLabel: String,
        visibleText: String,
        nearbyText: String,
        selectedText: String,
        selectedContext: String
    ) {
        self.init(
            title: title,
            documentKind: documentKind,
            locationLabel: locationLabel,
            visibleText: visibleText,
            nearbyText: nearbyText,
            focusedSelection: ReaderFocusedSelection.resolve(
                explicitSelection: selectedText,
                readAloudSelection: "",
                contextProvider: { _ in selectedContext }
            )
        )
    }

    package var selectedText: String {
        focusedSelection?.text ?? ""
    }

    package var selectedContext: String {
        focusedSelection?.context ?? ""
    }

    package var currentContentTitle: String {
        let trimmedLocation = trimmed(locationLabel)
        return trimmedLocation.isEmpty ? title : "\(title) - \(trimmedLocation)"
    }

    package var readingText: String {
        let visible = trimmed(visibleText)
        if !visible.isEmpty { return visible }
        return trimmed(nearbyText)
    }

    package var focusedReadingText: String {
        let selected = trimmed(selectedText)
        return selected.isEmpty ? readingText : selected
    }

    package var contextText: String {
        var parts: [String] = []
        if hasTrimmedText(locationLabel) {
            parts.append(AppText.localized("【当前位置】\n\(locationLabel)", "[Current location]\n\(locationLabel)"))
        }
        if let focusedSelection, hasTrimmedText(focusedSelection.text) {
            let title = focusedSelection.origin == .readAloudSegment
                ? AppText.localized("【当前朗读内容】", "[Current read-aloud text]")
                : AppText.localized("【当前选中内容】", "[Selected text]")
            parts.append("\(title)\n\(focusedSelection.text)")
        }
        if let focusedSelection, hasTrimmedText(focusedSelection.context) {
            let title = focusedSelection.origin == .readAloudSegment
                ? AppText.localized("【朗读内容附近上下文】", "[Read-aloud context]")
                : AppText.localized("【选中内容附近上下文】", "[Selection context]")
            parts.append("\(title)\n\(focusedSelection.context)")
        }
        if hasTrimmedText(nearbyText) {
            parts.append(AppText.localized("【当前位置附近内容】\n\(nearbyText)", "[Nearby reading text]\n\(nearbyText)"))
        }
        return String(parts.joined(separator: "\n\n").prefix(5000))
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func hasTrimmedText(_ text: String) -> Bool {
        !trimmed(text).isEmpty
    }
}
