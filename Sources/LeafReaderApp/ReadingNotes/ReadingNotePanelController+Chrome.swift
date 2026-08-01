import Cocoa
import SwiftUI
import LeafReaderCore

extension ReadingNotePanelController {
    func makeEditorChromeView(theme: ReaderTheme) -> ReadingNoteEditorChromeView {
        ReadingNoteEditorChromeView(
            model: editorModel,
            theme: theme,
            onShowNotes: { [weak self] in
                self?.closeAfterSwiftUIChromeAction {
                    self?.onShowNotes()
                }
            },
            onMore: { [weak self] in
                self?.showMoreMenuFromSwiftUIChrome()
            }
        )
    }

    func updateEditorChromeTheme(_ theme: ReaderTheme) {
        editorChromeHostingView?.rootView = makeEditorChromeView(theme: theme)
        editorStatusHostingView?.rootView = ReadingNoteEditorStatusView(model: editorModel, theme: theme)
        editorWordCountHostingView?.rootView = ReadingNoteEditorWordCountView(model: editorModel, theme: theme)
    }

    private func closeAfterSwiftUIChromeAction(_ action: () -> Void) {
        save()
        editorModel.savesOnClose = false
        close()
        action()
    }

    private func showMoreMenuFromSwiftUIChrome() {
        guard let button = editorChromeHostingView else { return }
        let point = NSPoint(x: button.bounds.maxX - 18, y: button.bounds.minY + 18)
        presentMoreMenu(in: button, at: point)
    }
}
