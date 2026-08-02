import Observation
import SwiftUI
import LeafReaderCore

/// One TTS runtime's row: what it is, what it is doing, and what can be done to
/// it. Derived entirely from `SpeechRuntimeResourceManager`; the panel refreshes
/// these while a download runs.
struct SpeechRuntimeRowState: Identifiable {
    let id: String
    let title: String
    var status: String
    var isDownloaded: Bool
    var isDownloading: Bool
    var isPaused: Bool
    /// 0...1 while downloading, nil otherwise.
    var progress: Double?
}

/// A pick-one option in the Read Aloud page's three menus.
struct SpeechChoice: Identifiable, Hashable {
    let id: String
    let title: String
}

/// State behind the Read Aloud settings page.
///
/// The runtime / voice / speed menus are **pending** — saved by the panel's
/// Save, like the other pages. The runtime rows below them are **live**: the
/// panel owns the downloading, deleting and error alerts (they need sheets and
/// the resource manager), and pushes the resulting state in here through
/// `applyRuntimes(_:)`.
@Observable
final class SpeechSettingsModel: SettingsPage {
    var runtimeID: String {
        didSet {
            guard runtimeID != oldValue else { return }
            onRuntimeChanged?(runtimeID)
        }
    }

    var voiceID: String {
        didSet {
            guard voiceID != oldValue else { return }
            onVoiceChanged?(voiceID)
        }
    }

    var speedID: String

    var runtimeOptions: [SpeechChoice] = []
    var voiceOptions: [SpeechChoice] = []
    var speedOptions: [SpeechChoice] = []
    var runtimes: [SpeechRuntimeRowState] = []

    @ObservationIgnored var onRuntimeChanged: ((String) -> Void)?
    @ObservationIgnored var onVoiceChanged: ((String) -> Void)?
    @ObservationIgnored var onDownload: ((String) -> Void)?
    @ObservationIgnored var onTogglePaused: ((String) -> Void)?
    @ObservationIgnored var onCancelDownload: ((String) -> Void)?
    @ObservationIgnored var onDelete: ((String) -> Void)?
    @ObservationIgnored var onCopyDiagnostics: (() -> Void)?

    init(runtimeID: String, voiceID: String, speedID: String) {
        self.runtimeID = runtimeID
        self.voiceID = voiceID
        self.speedID = speedID
    }

    /// Replaces the menus without re-firing the change callbacks — used when the
    /// panel adjusts the selection itself (a language switch, or a runtime
    /// becoming runnable after its download finishes).
    func setSelection(runtimeID: String? = nil, voiceID: String? = nil) {
        if let runtimeID, runtimeID != self.runtimeID {
            let handler = onRuntimeChanged
            onRuntimeChanged = nil
            self.runtimeID = runtimeID
            onRuntimeChanged = handler
        }
        if let voiceID, voiceID != self.voiceID {
            let handler = onVoiceChanged
            onVoiceChanged = nil
            self.voiceID = voiceID
            onVoiceChanged = handler
        }
    }

    func applyRuntimes(_ rows: [SpeechRuntimeRowState]) {
        runtimes = rows
    }

    // MARK: - Rows

    /// The buttons for one runtime. Which ones exist depends on what it is
    /// doing: idle offers Download, a running download offers Pause/Resume and
    /// Cancel, an installed runtime offers Delete.
    func actions(for row: SpeechRuntimeRowState) -> [SettingsAction] {
        var actions: [SettingsAction] = []
        if !row.isDownloaded, !row.isDownloading {
            actions.append(SettingsAction(
                id: "\(SpeechSettingsAccessibility.downloadPrefix)\(row.id)",
                title: AppText.localized("下载 \(row.title)", "Download \(row.title)"),
                symbol: "arrow.down.circle",
                tint: Color(red: 0.00, green: 0.48, blue: 1.00),
                perform: { [weak self] in self?.onDownload?(row.id) }
            ))
        }
        if row.isDownloading {
            actions.append(SettingsAction(
                id: "\(SpeechSettingsAccessibility.pausePrefix)\(row.id)",
                title: row.isPaused ? AppText.localized("继续", "Resume") : AppText.localized("暂停", "Pause"),
                symbol: row.isPaused ? "play.circle" : "pause.circle",
                tint: Color(red: 1.00, green: 0.58, blue: 0.00),
                perform: { [weak self] in self?.onTogglePaused?(row.id) }
            ))
            actions.append(SettingsAction(
                id: "\(SpeechSettingsAccessibility.cancelPrefix)\(row.id)",
                title: AppText.localized("取消", "Cancel"),
                symbol: "minus.circle",
                tint: Color(red: 1.00, green: 0.22, blue: 0.28),
                perform: { [weak self] in self?.onCancelDownload?(row.id) }
            ))
        }
        if row.isDownloaded, !row.isDownloading {
            actions.append(SettingsAction(
                id: "\(SpeechSettingsAccessibility.deletePrefix)\(row.id)",
                title: AppText.localized("删除", "Delete"),
                symbol: "trash",
                role: .destructive,
                tint: Color(red: 1.00, green: 0.16, blue: 0.18),
                perform: { [weak self] in self?.onDelete?(row.id) }
            ))
        }
        return actions
    }

    var diagnosticsAction: SettingsAction {
        SettingsAction(
            id: SpeechSettingsAccessibility.diagnosticsButton,
            title: AppText.localized("复制诊断", "Copy Diagnostics"),
            symbol: "doc.on.clipboard",
            perform: { [weak self] in self?.onCopyDiagnostics?() }
        )
    }

    // MARK: - Saving

    /// Persisting needs the resource manager (a runtime is only selectable once
    /// it is runnable), so the panel does it; this just carries the choices.
    @ObservationIgnored var onCommit: ((String, String, String) -> Void)?

    func commit() {
        onCommit?(runtimeID, voiceID, speedID)
    }
}
