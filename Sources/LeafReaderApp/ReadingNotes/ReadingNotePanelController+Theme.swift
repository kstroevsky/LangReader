import Cocoa

extension ReadingNotePanelController {
    func applyTheme(_ theme: ReaderTheme) {
        let background = ReadingNoteTheme.panelBackground(theme)
        let text = ReadingNoteTheme.primaryText(theme)
        window?.backgroundColor = background
        window?.appearance = theme == .dark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        rootView.layer?.backgroundColor = background.cgColor
        rootView.layer?.cornerRadius = 18
        editorContainer.layer?.backgroundColor = ReadingNoteTheme.editorBackground(theme).cgColor
        editorContainer.layer?.cornerRadius = 9
        editorContainer.layer?.borderWidth = 1
        editorContainer.layer?.borderColor = ReadingNoteTheme.panelBorder(theme).cgColor
        textView.backgroundColor = ReadingNoteTheme.editorBackground(theme)
        textView.insertionPointColor = text
        applyTextColor(text, in: rootView)
        applyControlTint(text, in: rootView)
        aiToolbarContainer.layer?.backgroundColor = ReadingNoteTheme.cardBackground(theme).cgColor
        aiToolbarContainer.layer?.borderWidth = 1
        aiToolbarContainer.layer?.borderColor = ReadingNoteTheme.panelBorder(theme).cgColor
        askInputContainer.layer?.backgroundColor = ReadingNoteTheme.cardBackground(theme).cgColor
        askInputContainer.layer?.borderWidth = 1
        askInputContainer.layer?.borderColor = ReadingNoteTheme.panelBorder(theme).cgColor
        askInputField.textColor = text
        askSendButton.contentTintColor = text
        aiActionButtons.forEach {
            $0.layer?.backgroundColor = NSColor.clear.cgColor
            $0.contentTintColor = text
        }
        updateEditorChromeTheme(theme)
    }

    private func applyTextColor(_ color: NSColor, in view: NSView) {
        for subview in view.subviews {
            if let label = subview as? NSTextField, !label.isEditable {
                label.textColor = color
            }
            applyTextColor(color, in: subview)
        }
    }

    private func applyControlTint(_ color: NSColor, in view: NSView) {
        for subview in view.subviews {
            if let button = subview as? NSButton {
                button.contentTintColor = color
            }
            applyControlTint(color, in: subview)
        }
    }
}
