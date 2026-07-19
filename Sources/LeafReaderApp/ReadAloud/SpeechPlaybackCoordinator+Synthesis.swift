import Foundation

extension SpeechPlaybackCoordinator {
    func shutdown() {
        DispatchQueue.main.async {
            self.idleShutdownWorkItem?.cancel()
            self.idleShutdownWorkItem = nil
        }
        queue.async {
            self.forceTerminateRuntimeProcesses()
        }
        DispatchQueue.main.async {
            self.stopAndClearPlayback()
        }
    }

    func shutdownRuntime(_ runtime: SpeechRuntimeResourceManager.Runtime) {
        let targetRuntime = SpeechSynthesisRuntime(runtime: runtime)
        queue.async {
            guard self.activeRuntime != targetRuntime else {
                DispatchQueue.main.async {
                    self.shutdown()
                }
                return
            }
            targetRuntime.stop(using: self.runtimeAdapters)
        }
    }

    func stopKokoroWorkerIfLanguageDiffers(from text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        queue.async {
            self.runtimeAdapters.kokoro.stopIfLanguageDiffers(from: trimmed)
            guard SpeechSynthesisRuntime.selected(for: trimmed) == .kokoroCoreML else { return }
            self.runtimeAdapters.kokoro.prewarmIfNeeded(text: trimmed)
        }
    }

    func shutdownForTermination() {
        idleShutdownWorkItem?.cancel()
        idleShutdownWorkItem = nil
        stopAndClearPlayback()
        forceTerminateRuntimeProcesses()
    }

    func cancelScheduledIdleShutdown() {
        DispatchQueue.main.async {
            self.idleShutdownWorkItem?.cancel()
            self.idleShutdownWorkItem = nil
        }
    }

    func scheduleIdleShutdown() {
        idleShutdownWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.queue.async {
                self.forceTerminateRuntimeProcesses()
            }
        }
        idleShutdownWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleShutdownDelay, execute: workItem)
    }

    func generateWAV(
        text: String,
        outputURL: URL,
        voiceID: String? = nil,
        languageHint: AISettingsStore.SpeechLanguageHint? = nil
    ) -> Bool {
        generateWAVResult(
            text: text,
            outputURL: outputURL,
            voiceID: voiceID,
            languageHint: languageHint
        ).isSuccess
    }

    func consumeLastSynthesisError() -> SpeechSynthesisError? {
        if Thread.isMainThread {
            let error = lastSynthesisError
            lastSynthesisError = nil
            return error
        }
        var error: SpeechSynthesisError?
        DispatchQueue.main.sync {
            error = self.lastSynthesisError
            self.lastSynthesisError = nil
        }
        return error
    }

    func generateWAVResult(
        text: String,
        outputURL: URL,
        voiceID: String? = nil,
        languageHint: AISettingsStore.SpeechLanguageHint? = nil,
        options: SynthesisOptions = .default,
        recordFailure: Bool = true
    ) -> Result<Void, SpeechSynthesisError> {
        let synthesisRuntime = SpeechSynthesisRuntime.selected(for: text, languageHint: languageHint)
        prepareForRuntime(synthesisRuntime)
        let runtime = synthesisRuntime.runtime
        let request = SpeechSynthesisRequest(
            text: text,
            outputURL: outputURL,
            voiceID: voiceID,
            languageHint: languageHint,
            speedMultiplier: options.speedMultiplier,
            piperLengthScale: options.piperLengthScale
        )
        let result = synthesisRuntime.synthesize(request, using: runtimeAdapters)
        switch result {
        case .success:
            if let runtime {
                SpeechRuntimeInferenceFailureStore.clear(for: runtime)
            }
        case .failure(let error):
            if recordFailure {
                recordSynthesisFailure(
                    error,
                    text: text,
                    outputURL: outputURL,
                    voiceID: voiceID,
                    languageHint: languageHint
                )
            }
        }
        return result
    }

    func recordSynthesisFailure(
        _ error: SpeechSynthesisError,
        text: String,
        outputURL: URL,
        voiceID: String?,
        languageHint: AISettingsStore.SpeechLanguageHint?,
        context: String = "readAloud"
    ) {
        let synthesisRuntime = SpeechSynthesisRuntime.selected(for: text, languageHint: languageHint)
        let runtime = synthesisRuntime.runtime
        let effectiveVoiceID = runtime.map {
            voiceID ?? AISettingsStore.selectedSpeechVoiceID(runtimeID: $0.id)
        }
        if let runtime {
            SpeechRuntimeInferenceFailureStore.record(
                error,
                for: runtime,
                voiceID: effectiveVoiceID,
                context: context,
                text: text,
                outputURL: outputURL
            )
        }
        logSynthesisFailure(
            error,
            runtime: runtime,
            voiceID: effectiveVoiceID,
            text: text,
            outputURL: outputURL
        )
        DispatchQueue.main.async {
            self.lastSynthesisError = error
        }
    }

    func prepareForRuntime(_ runtime: SpeechSynthesisRuntime) {
        guard activeRuntime != runtime else { return }
        runtime.stopOtherRuntimes(using: runtimeAdapters)
        activeRuntime = runtime
    }

    func forceTerminateRuntimeProcesses() {
        runtimeAdapters.stopAll()
        activeRuntime = nil
    }

    private func logSynthesisFailure(
        _ error: SpeechSynthesisError,
        runtime: SpeechRuntimeResourceManager.Runtime?,
        voiceID: String?,
        text: String,
        outputURL: URL
    ) {
        NSLog(
            "LeafReader TTS inference failed runtime=%@ voice=%@ textLength=%d output=%@ error=%@",
            runtime?.id ?? "none",
            voiceID ?? "none",
            text.count,
            outputURL.path,
            error.localizedDescription
        )
    }

}
