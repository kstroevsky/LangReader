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
            },
            onToggleFavorite: { [weak self] in
                guard let self else { return }
                self.setFavorite(!self.editorModel.isFavorite)
            }
        )
    }

    func makeEditorActionToolbarView(theme: ReaderTheme) -> ReadingNoteEditorToolbarView {
        ReadingNoteEditorToolbarView(
            model: editorModel,
            theme: theme,
            onSave: { [weak self] in self?.saveTappedFromSwiftUI() },
            onUndo: { [weak self] in self?.performUndo() },
            onRedo: { [weak self] in self?.performRedo() }
        )
    }

    func makeEditorStatusView(theme: ReaderTheme) -> ReadingNoteEditorStatusView {
        ReadingNoteEditorStatusView(
            model: editorModel,
            theme: theme,
            onCancelAI: { [weak self] in self?.cancelAIRequestFromSwiftUI() }
        )
    }

    func updateEditorChromeTheme(_ theme: ReaderTheme) {
        editorChromeHostingView?.rootView = makeEditorChromeView(theme: theme)
        editorActionToolbarHostingView?.rootView = makeEditorActionToolbarView(theme: theme)
        editorStatusHostingView?.rootView = makeEditorStatusView(theme: theme)
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

    private func saveTappedFromSwiftUI() {
        autoSaveTask.cancel()
        save()
        editorModel.statusSaved()
    }

    private func cancelAIRequestFromSwiftUI() {
        cleanupActiveAIRequest()
    }
}
