import Cocoa
import SwiftUI

extension AISettingsPanelController {
    /// Fills the Model page with the SwiftUI form.
    ///
    /// Same shape as the General page: one hosting view pinned to the page,
    /// with the tab strip, Save and Cancel left alone.
    func installModelSettingsPage(in page: NSView) {
        let model = ModelSettingsModel()
        model.onTestConnection = { [weak self] in
            self?.testChatConnection()
        }
        modelSettings = model

        installSettingsPage(ModelSettingsView(model: model), in: page)
    }

    /// Fills the AI Analysis page with the SwiftUI form.
    func installEmbeddingSettingsPage(in page: NSView) {
        let model = EmbeddingSettingsModel()
        model.onTestConnection = { [weak self] in
            self?.testEmbeddingConnection()
        }
        embeddingSettings = model

        installSettingsPage(EmbeddingSettingsView(model: model), in: page)
    }

    /// Fills the Read Aloud page with the SwiftUI form.
    func installSpeechSettingsPage(in page: NSView) {
        let languageHint = currentSpeechLanguageHint?()
        syncSpeechRuntimeForLanguageIfNeeded(languageHint: languageHint)
        let runtimeID = effectiveSelectedSpeechRuntimeID(languageHint: languageHint)
        let model = SpeechSettingsModel(
            runtimeID: runtimeID,
            voiceID: AISettingsStore.selectedSpeechVoiceID(runtimeID: runtimeID),
            speedID: AISettingsStore.selectedSpeechSpeedID
        )
        model.speedOptions = AISettingsStore.speechSpeedOptions.map { SpeechChoice(id: $0.id, title: $0.title) }
        model.onRuntimeChanged = { [weak self] id in self?.speechRuntimeChanged(to: id) }
        model.onVoiceChanged = { [weak self] id in self?.speechVoiceChanged(to: id) }
        model.onDownload = { [weak self] id in self?.runtime(for: id).map { self?.downloadSpeechRuntime($0) } }
        model.onTogglePaused = { [weak self] id in self?.runtime(for: id).map { self?.toggleSpeechRuntimeDownloadPaused($0) } }
        model.onCancelDownload = { [weak self] id in self?.runtime(for: id).map { self?.cancelSpeechRuntimeDownload($0) } }
        model.onDelete = { [weak self] id in self?.runtime(for: id).map { self?.deleteSpeechRuntime($0) } }
        model.onCopyDiagnostics = { [weak self] in self?.copySpeechRuntimeDiagnostics(error: nil, runtime: nil) }
        model.onCommit = { [weak self] runtimeID, voiceID, speedID in
            self?.saveSelectedSpeechSettings(runtimeID: runtimeID, voiceID: voiceID, speedID: speedID)
        }
        speechSettings = model

        installSettingsPage(SpeechSettingsView(model: model), in: page)
    }

    func runtime(for id: String) -> SpeechRuntimeResourceManager.Runtime? {
        SpeechRuntimeResourceManager.Runtime.runtime(for: id)
    }

    /// Fills the Cache page with the SwiftUI form.
    func installCacheSettingsPage(in page: NSView) {
        let model = CacheSettingsModel()
        model.onBuildCurrentIndex = { [weak self] in self?.startCurrentVectorIndex() }
        model.onTogglePaused = { [weak self] in self?.toggleCurrentVectorIndex() }
        model.onCancelIndexing = { [weak self] in self?.cancelCurrentVectorIndex() }
        model.onClearCurrentIndex = { [weak self] in self?.clearCurrentVectorIndex() }
        model.onClearCurrentWords = { [weak self] in self?.onClearCurrentWordRecords?() }
        model.onClearAllCache = { [weak self] in self?.clearVectorCache() }
        cacheSettings = model

        installSettingsPage(CacheSettingsView(model: model), in: page)
    }

    func installVocabularySettingsPage(in page: NSView) {
        let model = VocabularySettingsModel()
        vocabularySettings = model
        installSettingsPage(VocabularySettingsView(model: model), in: page)
    }
}
