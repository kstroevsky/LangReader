import Foundation
import Observation
import LeafReaderCore

/// State behind the note editor.
///
/// The editor itself stays AppKit — it is an AppKit text view doing
/// attributed-string editing, which SwiftUI has no equivalent for on macOS 14
/// (naming the class here would exclude this file from the logic-test build,
/// which greps for AppKit type names) — but everything
/// *around* the text is plain state and lives here: the note being edited, the
/// text derived from it (word count, location, timestamps), the status line, and
/// the lifecycle of an in-flight AI request.
///
/// Two things this fixes by construction:
///
///   * the status line was written from **13 places** across four files as raw
///     string assignments to a label; the transitions are named here instead, so
///     they can be read in one place and tested;
///   * the AI request lifecycle lived in a struct that also held an event
///     monitor and a `DispatchWorkItem`, which made it untestable. Those stay
///     with the controller; the decision "may this result still be applied?"
///     does not.
@Observable
final class ReadingNoteEditorModel {
    private(set) var note: ReadingNote

    /// The editor's text **as displayed**, which is what the word count reports:
    /// `**bold**` is four characters here, eight in the markdown source.
    ///
    /// It is deliberately not what gets persisted. This field used to hold both —
    /// `save()` assigned the markdown projection, `updateWordCount()` assigned the
    /// rendered string, and `commitEdits()` wrote whichever landed last into
    /// `note.markdown`. That was correct only because `save()` happened to assign
    /// immediately before committing; any other order would have persisted the
    /// rendered text as the source and dropped the formatting. Committing now
    /// takes the markdown as an argument.
    private(set) var text: String = ""

    /// The transient message under the editor ("Saved", "Markdown copied", an
    /// error). Set through the named transitions below rather than directly.
    private(set) var statusMessage: String = ""

    /// True between a change and the save that follows it.
    private(set) var hasUnsavedChanges = false

    /// Cleared when the note is closed without saving (an explicit save already
    /// happened, or the user discarded).
    var savesOnClose = true

    /// Set while the window is tearing down, so a late AI response cannot write
    /// into a dead editor.
    var isClosing = false

    /// The text the user had selected when they opened the Ask box, held until
    /// the question is sent.
    var pendingAskSelectedText = ""

    /// The placeholder shown in the editor while an AI action runs, so the
    /// result can replace exactly that range.
    var aiPlaceholderDisplayText: String?

    private var activeAIRequestID: UUID?

    /// True while an AI action is running, for the toolbar's busy state.
    var isRunningAIRequest: Bool { activeAIRequestID != nil }

    init(note: ReadingNote) {
        self.note = note
        text = note.markdown
        hasUnsavedChanges = false
    }

    // MARK: - Derived display text

    var wordCountText: String {
        let count = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        return AppText.localized("\(count) 字", "\(count) chars")
    }

    /// Where in the document the note was taken — a PDF page or a scroll
    /// percentage.
    var locationText: String {
        if let first = note.locator.pdfFragments?.first {
            return AppText.localized("Page \(first.pageIndex + 1)", "Page \(first.pageIndex + 1)")
        }
        let percent = Int((note.locator.webAnchor?.scrollProgress ?? 0) * 100)
        return AppText.localized("网页位置 \(percent)%", "Web \(percent)%")
    }

    var createdAtText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: note.createdAt)
    }

    var isFavorite: Bool { note.isFavorite }

    // MARK: - Editing

    /// The user typed. Marks the note dirty only when the text actually changed,
    /// so a refresh that re-reads the same string cannot fake an edit.
    func userDidEdit(_ newText: String) {
        guard newText != text else { return }
        text = newText
        hasUnsavedChanges = true
    }

    /// Mirrors the view's text without implying an edit — used after a render or
    /// when the word count is refreshed. Previously this went through the same
    /// assignment as typing, so every refresh marked the note unsaved; because
    /// `commitEditorChange()` refreshes *after* saving, a note was dirty again
    /// the instant it had been saved.
    func syncText(_ newText: String) {
        text = newText
    }

    /// Folds the given markdown into the note and stamps it. Returns the note to
    /// persist, so the caller does not have to reach back in for it.
    @discardableResult
    func commitEdits(markdown: String, now: Date = Date()) -> ReadingNote {
        note.markdown = markdown
        note.updatedAt = now
        hasUnsavedChanges = false
        return note
    }

    @discardableResult
    func toggleFavorite() -> ReadingNote {
        setFavorite(!note.isFavorite)
    }

    /// Sets the flag rather than flipping it, for changes that originate outside
    /// the editor. The notes list knows the state it wants; a toggle there would
    /// resolve against whichever copy it happened to read.
    @discardableResult
    func setFavorite(_ isFavorite: Bool) -> ReadingNote {
        note.isFavorite = isFavorite
        status(note.isFavorite
            ? AppText.localized("已收藏", "Favorited")
            : AppText.localized("已取消收藏", "Favorite removed"))
        return note
    }

    /// Replaces the note wholesale — used when a template is applied or the
    /// editor is re-pointed at a note reloaded from the store.
    func replaceNote(_ note: ReadingNote) {
        self.note = note
        text = note.markdown
        hasUnsavedChanges = false
    }

    // MARK: - Status line

    func clearStatus() { statusMessage = "" }
    func status(_ message: String) { statusMessage = message }

    func statusSaved() { status(AppText.localized("已保存", "Saved")) }
    func statusMarkdownCopied() { status(AppText.localized("已复制 Markdown", "Markdown copied")) }
    func statusSelectionRequired() {
        status(AppText.localized("请先选中笔记中的文字", "Select text in the note first"))
    }
    func statusAPIKeyRequired() {
        status(AppText.localized("请先配置 API Key", "Configure API Key first"))
    }
    /// "Translating…" while an action runs, cleared when it stops.
    func statusRunning(_ title: String, isRunning: Bool) {
        status(isRunning ? AppText.localized("\(title)中...", "\(title)...") : "")
    }

    // MARK: - AI request lifecycle

    func beginAIRequest() -> UUID {
        let id = UUID()
        activeAIRequestID = id
        return id
    }

    /// A result may be applied only if it belongs to the newest request and the
    /// editor is still open — otherwise a slow response would overwrite a newer
    /// one, or write into a closing window.
    func canApplyAIResult(_ id: UUID) -> Bool {
        !isClosing && activeAIRequestID == id
    }

    func finishAIRequest(_ id: UUID) {
        if activeAIRequestID == id {
            activeAIRequestID = nil
        }
    }

    func cancelAIRequests() {
        activeAIRequestID = nil
    }
}
