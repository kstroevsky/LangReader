import Cocoa

extension AISettingsPanelController {
    private enum SpeechPreview {
        static let selectionDebounce: TimeInterval = 0.3
    }

    private struct RuntimeStatus {
        let downloaded: Bool
        let downloading: Bool
        let paused: Bool
    }

    func speechRuntimeChanged(to runtimeID: String) {
        guard let runtime = SpeechRuntimeResourceManager.Runtime.runtime(for: runtimeID),
              !speechRuntimeIsBlockedByLanguage(runtime, languageHint: currentSpeechLanguageHint?()),
              SpeechRuntimeResourceManager.isRunnable(runtime) else {
            // Not selectable: snap the picker back to what is actually in use.
            // The AppKit popup disabled these items outright, which SwiftUI's
            // Picker cannot do per-item.
            refreshSpeechRuntimeStatus()
            return
        }
        saveSelectedSpeechSettings(
            runtimeID: runtimeID,
            voiceID: speechSettings?.voiceID,
            speedID: speechSettings?.speedID
        )
        refreshSpeechVoiceOptions(runtimeID: runtimeID)
        refreshSpeechRuntimeStatus()
    }

    func speechVoiceChanged(to voiceID: String) {
        let runtimeID = speechSettings?.runtimeID
        saveSelectedSpeechSettings(
            runtimeID: runtimeID,
            voiceID: voiceID,
            speedID: speechSettings?.speedID
        )
        previewSelectedSpeechVoice(voiceID, runtimeID: runtimeID)
    }

    func refreshSpeechRuntimeStatus() {
        let statuses = Dictionary(
            uniqueKeysWithValues: SpeechRuntimeResourceManager.Runtime.displayOrder.map { ($0, runtimeStatus($0)) }
        )
        speechSettings?.applyRuntimes(SpeechRuntimeResourceManager.Runtime.displayOrder.compactMap { runtime in
            guard let status = statuses[runtime] else { return nil }
            return SpeechRuntimeRowState(
                id: runtime.id,
                title: runtime.title,
                status: SpeechRuntimeResourceManager.statusText(for: runtime),
                isDownloaded: status.downloaded,
                isDownloading: status.downloading,
                isPaused: status.paused,
                progress: status.downloading
                    ? (SpeechRuntimeResourceManager.downloadProgress(for: runtime) ?? 0)
                    : nil
            )
        })
        refreshSpeechRuntimeOptions()
        updateSpeechDownloadRefreshTimer(isDownloading: statuses.values.contains { $0.downloading })
    }

    private func runtimeStatus(_ runtime: SpeechRuntimeResourceManager.Runtime) -> RuntimeStatus {
        RuntimeStatus(
            downloaded: SpeechRuntimeResourceManager.isDownloaded(runtime),
            downloading: SpeechRuntimeResourceManager.isDownloading(runtime),
            paused: SpeechRuntimeResourceManager.isPaused(runtime)
        )
    }

    func toggleSpeechRuntimeDownloadPaused(_ runtime: SpeechRuntimeResourceManager.Runtime) {
        if SpeechRuntimeResourceManager.isPaused(runtime) {
            SpeechRuntimeResourceManager.resume(runtime)
        } else {
            SpeechRuntimeResourceManager.pause(runtime)
        }
        refreshSpeechRuntimeStatus()
    }

    func cancelSpeechRuntimeDownload(_ runtime: SpeechRuntimeResourceManager.Runtime) {
        SpeechRuntimeResourceManager.cancel(runtime)
        refreshSpeechRuntimeStatus()
    }

    private func updateSpeechDownloadRefreshTimer(isDownloading: Bool) {
        if isDownloading {
            guard speechDownloadRefreshTimer == nil else { return }
            speechDownloadRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.refreshSpeechRuntimeStatus()
            }
        } else {
            speechDownloadRefreshTimer?.invalidate()
            speechDownloadRefreshTimer = nil
        }
    }

    func saveSelectedSpeechSettings(
        runtimeID: String?,
        voiceID: String?,
        speedID: String?
    ) {
        let previousRuntimeID = AISettingsStore.selectedSpeechRuntimeID
        let targetRuntimeID = runtimeID ?? previousRuntimeID

        if let voiceID {
            AISettingsStore.saveSpeechVoiceID(voiceID, runtimeID: targetRuntimeID)
        }
        if let speedID {
            AISettingsStore.saveSpeechSpeedID(speedID)
        }

        guard let runtimeID,
              let runtime = SpeechRuntimeResourceManager.Runtime.runtime(for: runtimeID),
              SpeechRuntimeResourceManager.isRunnable(runtime) else {
            return
        }

        AISettingsStore.saveSelectedSpeechRuntimeID(runtimeID)

        let runtimeChanged = runtimeID != previousRuntimeID
        if runtimeChanged, !SpeechPlaybackCoordinator.shared.hasActiveReadAloudWork() {
            SpeechPlaybackCoordinator.shared.shutdown()
        }
    }

    /// Rebuilds the runtime menu. Runtimes that cannot be used keep their place
    /// with the reason appended to the title, exactly as the AppKit popup did.
    private func refreshSpeechRuntimeOptions() {
        guard let model = speechSettings else { return }
        let languageHint = currentSpeechLanguageHint?()
        syncSpeechRuntimeForLanguageIfNeeded(languageHint: languageHint)
        let runnableRuntimes = SpeechRuntimeResourceManager.runnableReadAloudRuntimes()
        let selectedRuntime = selectedSpeechRuntimeForPopup(languageHint: languageHint, runnableRuntimes: runnableRuntimes)

        model.runtimeOptions = SpeechRuntimeResourceManager.Runtime.displayOrder.map { runtime in
            let blockedByLanguage = speechRuntimeIsBlockedByLanguage(runtime, languageHint: languageHint)
            let runnable = !blockedByLanguage && runnableRuntimes.contains(runtime)
            let title: String
            if runnable {
                title = runtime.title
            } else if blockedByLanguage {
                title = AppText.localized("\(runtime.title)（中文使用 Kokoro）", "\(runtime.title) (Chinese uses Kokoro)")
            } else if let reason = SpeechRuntimeResourceManager.availabilityText(for: runtime) {
                title = "\(runtime.title)（\(reason)）"
            } else {
                title = AppText.localized("\(runtime.title)（不可用）", "\(runtime.title) (Unavailable)")
            }
            return SpeechChoice(id: runtime.id, title: title)
        }

        let effectiveID = selectedRuntime?.id ?? model.runtimeOptions.first?.id
        model.setSelection(runtimeID: effectiveID)
        refreshSpeechVoiceOptions(runtimeID: effectiveID)
    }

    /// Rebuilds the voice menu for a runtime, keeping the saved voice selected
    /// and falling back to the first when the saved one is not offered.
    func refreshSpeechVoiceOptions(runtimeID: String?) {
        guard let model = speechSettings else { return }
        let runtimeID = runtimeID ?? AISettingsStore.selectedSpeechRuntimeID
        let languageHint = currentSpeechLanguageHint?()
        let options = AISettingsStore.speechVoiceOptions(runtimeID: runtimeID, languageHint: languageHint)
        model.voiceOptions = options.map { SpeechChoice(id: $0.id, title: $0.title) }

        let savedVoiceID = AISettingsStore.selectedSpeechVoiceID(runtimeID: runtimeID)
        if options.contains(where: { $0.id == savedVoiceID }) {
            model.setSelection(voiceID: savedVoiceID)
        } else if let fallback = options.first {
            model.setSelection(voiceID: fallback.id)
            AISettingsStore.saveSpeechVoiceID(fallback.id, runtimeID: runtimeID)
        }
    }

    private func previewSelectedSpeechVoice(_ voiceID: String?, runtimeID: String?) {
        guard let voiceID,
              let runtimeID,
              let runtime = SpeechRuntimeResourceManager.Runtime.runtime(for: runtimeID),
              SpeechRuntimeResourceManager.isRunnable(runtime),
              !SpeechPlaybackCoordinator.shared.hasActiveReadAloudWork() else {
            return
        }
        let voiceTitle = AISettingsStore.speechVoiceTitle(for: voiceID, runtimeID: runtime.id)
        let languageHint = currentSpeechLanguageHint?()
        let text = runtime == .kokoro && languageHint == .chinese
            ? "欢迎使用叶子阅读，我是\(voiceTitle)，下面由我来给你阅读这本书。"
            : "Welcome to Leaf Vocabulary. I'm \(voiceTitle), and I'll be reading this book for you. Enjoy!"
        let speedID = AISettingsStore.selectedSpeechSpeedID
        speechVoicePreviewWorkItem?.cancel()
        if runtime == .kokoro {
            SpeechPlaybackCoordinator.shared.cancelCurrentSpeechPreview(terminateKokoroWorker: true)
        }
        let workItem = DispatchWorkItem {
            SpeechPlaybackCoordinator.shared.speakCachedPreviewInterruption(
                text,
                runtimeID: runtime.id,
                voiceID: voiceID,
                speedID: speedID
            ) { [weak self] _ in
                self?.refreshSpeechRuntimeStatus()
            } finished: {
            }
        }
        speechVoicePreviewWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + SpeechPreview.selectionDebounce, execute: workItem)
    }

    func effectiveSelectedSpeechRuntimeID(languageHint: AISettingsStore.SpeechLanguageHint?) -> String {
        languageHint == .chinese
            ? SpeechRuntimeResourceManager.Runtime.kokoro.id
            : AISettingsStore.selectedSpeechRuntimeID
    }

    func syncSpeechRuntimeForLanguageIfNeeded(languageHint: AISettingsStore.SpeechLanguageHint?) {
        guard languageHint == .chinese,
              SpeechRuntimeResourceManager.isRunnable(.kokoro),
              AISettingsStore.selectedSpeechRuntimeID != SpeechRuntimeResourceManager.Runtime.kokoro.id else {
            return
        }
        AISettingsStore.saveSelectedSpeechRuntimeID(SpeechRuntimeResourceManager.Runtime.kokoro.id)
    }

    private func selectedSpeechRuntimeForPopup(
        languageHint: AISettingsStore.SpeechLanguageHint?,
        runnableRuntimes: [SpeechRuntimeResourceManager.Runtime]
    ) -> SpeechRuntimeResourceManager.Runtime? {
        if languageHint == .chinese {
            return SpeechRuntimeResourceManager.isRunnable(.kokoro) ? .kokoro : nil
        }
        return runnableRuntimes.first { $0.id == AISettingsStore.selectedSpeechRuntimeID }
            ?? runnableRuntimes.first
    }

    private func speechRuntimeIsBlockedByLanguage(
        _ runtime: SpeechRuntimeResourceManager.Runtime,
        languageHint: AISettingsStore.SpeechLanguageHint?
    ) -> Bool {
        languageHint == .chinese && runtime == .piper
    }

    func downloadSpeechRuntime(_ runtime: SpeechRuntimeResourceManager.Runtime) {
        guard runtime.isSupportedOnCurrentSystem else {
            showUnsupportedRuntimeDownloadWarning(runtime) { [weak self] shouldContinue in
                guard let self else { return }
                if shouldContinue {
                    self.startSpeechRuntimeDownload(runtime)
                } else {
                    self.refreshSpeechRuntimeStatus()
                }
            }
            return
        }

        startSpeechRuntimeDownload(runtime)
    }

    private func startSpeechRuntimeDownload(_ runtime: SpeechRuntimeResourceManager.Runtime) {
        // The button's enabled state used to be set here; it now follows from
        // the row's `isDownloading`, which `refreshSpeechRuntimeStatus` derives
        // from the resource manager.
        SpeechRuntimeResourceManager.download(runtime) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.selectSpeechRuntimeAfterDownload(runtime)
                self.refreshSpeechRuntimeStatus()
            case .failure(let error):
                guard (error as NSError).code != NSUserCancelledError else {
                    self.refreshSpeechRuntimeStatus()
                    return
                }
                self.refreshSpeechRuntimeStatus()
                self.showSpeechDownloadError(error, runtime: runtime)
            }
        }
        refreshSpeechRuntimeStatus()
    }

    private func showUnsupportedRuntimeDownloadWarning(
        _ runtime: SpeechRuntimeResourceManager.Runtime,
        completion: @escaping (Bool) -> Void
    ) {
        guard let panel else {
            completion(true)
            return
        }

        let alert = NSAlert()
        alert.messageText = AppText.localized("系统版本低于朗读模型要求", "System Version Below Runtime Requirement")
        alert.informativeText = AppText.localized(
            "\(runtime.title) 需要 \(runtime.minimumSystemVersionText) 或更高版本才能运行。你仍然可以下载模型，但当前系统可能无法使用它。",
            "\(runtime.title) requires \(runtime.minimumSystemVersionText) or later to run. You can still download the model, but this system may not be able to use it."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppText.localized("继续下载", "Download Anyway"))
        alert.addButton(withTitle: AppText.cancel)
        alert.beginSheetModal(for: panel) { response in
            completion(response == .alertFirstButtonReturn)
        }
    }

    private func selectSpeechRuntimeAfterDownload(_ downloadedRuntime: SpeechRuntimeResourceManager.Runtime) {
        let runnableRuntimes = SpeechRuntimeResourceManager.runnableReadAloudRuntimes()
        guard runnableRuntimes.contains(downloadedRuntime) else { return }

        let selectedRuntime = SpeechRuntimeResourceManager.Runtime.runtime(for: AISettingsStore.selectedSpeechRuntimeID)
        let selectedRuntimeIsRunnable = selectedRuntime.map { runnableRuntimes.contains($0) } ?? false
        guard runnableRuntimes.count == 1 || !selectedRuntimeIsRunnable else { return }

        let previousRuntimeID = AISettingsStore.selectedSpeechRuntimeID
        AISettingsStore.saveSelectedSpeechRuntimeID(downloadedRuntime.id)
        guard downloadedRuntime.id != previousRuntimeID else { return }
        if !SpeechPlaybackCoordinator.shared.hasActiveReadAloudWork() {
            SpeechPlaybackCoordinator.shared.shutdown()
        }
    }

    func deleteSpeechRuntime(_ runtime: SpeechRuntimeResourceManager.Runtime) {
        SpeechPlaybackCoordinator.shared.shutdownRuntime(runtime)
        do {
            try SpeechRuntimeResourceManager.delete(runtime)
            selectRunnableSpeechRuntimeIfNeeded(deletedRuntime: runtime)
            refreshSpeechRuntimeStatus()
        } catch {
            showSpeechDeleteError(error, runtime: runtime)
        }
    }

    private func selectRunnableSpeechRuntimeIfNeeded(deletedRuntime: SpeechRuntimeResourceManager.Runtime) {
        guard AISettingsStore.selectedSpeechRuntimeID == deletedRuntime.id else { return }
        guard let replacement = SpeechRuntimeResourceManager.runnableReadAloudRuntimes().first else { return }
        AISettingsStore.saveSelectedSpeechRuntimeID(replacement.id)
    }

    private func showSpeechDownloadError(_ error: Error, runtime: SpeechRuntimeResourceManager.Runtime) {
        guard let panel else { return }
        let alert = NSAlert()
        alert.messageText = AppText.localized("朗读模型下载失败", "Read Aloud Model Download Failed")
        alert.informativeText = speechRuntimeErrorDescription(error)
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppText.confirm)
        alert.addButton(withTitle: AppText.localized("复制诊断", "Copy Diagnostics"))
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard response == .alertSecondButtonReturn else { return }
            self?.copySpeechRuntimeDiagnostics(error: error, runtime: runtime)
        }
    }

    private func showSpeechDeleteError(_ error: Error, runtime: SpeechRuntimeResourceManager.Runtime) {
        guard let panel else { return }
        let alert = NSAlert()
        alert.messageText = AppText.localized("朗读模型删除失败", "Delete Read Aloud Model Failed")
        alert.informativeText = speechRuntimeErrorDescription(error)
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppText.confirm)
        alert.addButton(withTitle: AppText.localized("复制诊断", "Copy Diagnostics"))
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard response == .alertSecondButtonReturn else { return }
            self?.copySpeechRuntimeDiagnostics(error: error, runtime: runtime)
        }
    }

    private func speechRuntimeErrorDescription(_ error: Error) -> String {
        let raw = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = AppText.localized("未知错误", "Unknown error")
        return NetworkErrorFormatter.sanitizedBody(raw.isEmpty ? fallback : raw)
    }

    func copySpeechRuntimeDiagnostics(error: Error?, runtime: SpeechRuntimeResourceManager.Runtime?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(speechRuntimeDiagnosticText(error: error, runtime: runtime), forType: .string)
    }

    private func speechRuntimeDiagnosticText(
        error: Error?,
        runtime selectedRuntime: SpeechRuntimeResourceManager.Runtime?
    ) -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        var lines = [
            "Leaf Reader Speech Runtime Diagnostic",
            "version: \(version)",
            "selectedRuntime: \(AISettingsStore.selectedSpeechRuntimeID)",
            "selectedSpeed: \(AISettingsStore.selectedSpeechSpeedID)"
        ]
        if let error {
            lines.append("error: \(speechRuntimeErrorDescription(error))")
        }
        let runtimes: [SpeechRuntimeResourceManager.Runtime]
        if let selectedRuntime {
            runtimes = [selectedRuntime]
        } else {
            runtimes = SpeechRuntimeResourceManager.Runtime.displayOrder
        }
        for runtime in runtimes {
            let health = SpeechRuntimeAvailability.health(for: runtime)
            let failure = SpeechRuntimeInferenceFailureStore.failure(for: runtime)
            lines += [
                "",
                "[\(runtime.id)]",
                "title: \(runtime.title)",
                "voice: \(AISettingsStore.selectedSpeechVoiceID(runtimeID: runtime.id))",
                "supported: \(runtime.isSupportedOnCurrentSystem)",
                "minimumSystem: \(runtime.minimumSystemVersionText)",
                "downloaded: \(SpeechRuntimeResourceManager.isDownloaded(runtime))",
                "runnable: \(SpeechRuntimeResourceManager.isRunnable(runtime))",
                "downloading: \(SpeechRuntimeResourceManager.isDownloading(runtime))",
                "paused: \(SpeechRuntimeResourceManager.isPaused(runtime))",
                "installState: \(health.installState)",
                "hasRuntime: \(health.hasRuntime)",
                "hasModel: \(health.hasModel)",
                "status: \(SpeechRuntimeResourceManager.statusText(for: runtime))",
                "installDirectory: \(runtime.installDirectory.path)",
                "bundledExecutable: \(runtime.bundledExecutableURL?.path ?? "none")",
                "lastFailureContext: \(failure?.context ?? "none")",
                "lastFailureTextLength: \(failure.map { String($0.textLength) } ?? "none")",
                "lastFailureOutput: \(failure?.outputPath ?? "none")"
            ]
        }
        return lines.joined(separator: "\n")
    }
}
