import Cocoa
import AVFoundation
import LeafReaderCore

extension SpeechPlaybackCoordinator {
    @MainActor
    func speakCachedPreviewInterruption(
        _ text: String,
        runtimeID: String,
        voiceID: String,
        speedID: String,
        completion: @escaping (Bool) -> Void,
        finished: @escaping () -> Void
    ) {
        let callbacks = SpeechInterruptionCallbacks(completion: completion, finished: finished)
        cancelScheduledIdleShutdown()
        let value = SpeechTextPolicy.normalizedReadAloudInput(text)
        guard SpeechTextPolicy.isLocalTTSCandidate(value) else {
            callbacks.complete(false)
            return
        }

        let segment = SpeechTextPolicy.segments(for: value).joined(separator: " ")
        let cacheURL = TTSPreviewCache.audioURL(text: segment, runtimeID: runtimeID, voiceID: voiceID, speedID: speedID)
        let generationID = UUID()
        beginInterruptionGeneration(generationID)
        queue.async { [weak self] in
            guard let self else { return }
            guard self.isActiveInterruptionGeneration(generationID) else { return }
            if TTSWaveFile.isUsable(at: cacheURL) {
                NSLog("LeafReader TTS preview: cache hit runtime=%@ voice=%@ speed=%@ output=%@", runtimeID, voiceID, speedID, cacheURL.path)
                DispatchQueue.main.async {
                    guard self.activeInterruptionGenerationID == generationID else { return }
                    callbacks.complete(true)
                    self.playInterruptionOutput(cacheURL, removeAfterPlayback: false, callbacks: callbacks)
                }
                return
            }

            try? FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let tempURL = cacheURL.deletingLastPathComponent()
                .appendingPathComponent("pending-\(UUID().uuidString).wav")
            let result = self.generateWAVResult(
                text: segment,
                outputURL: tempURL,
                voiceID: voiceID,
                recordFailure: false
            )
            guard result.isSuccess,
                  TTSWaveFile.isUsable(at: tempURL) else {
                let error: SpeechSynthesisError?
                if case .failure(let value) = result {
                    error = value
                } else {
                    error = .invalidAudioOutput(SpeechRuntimeResourceManager.Runtime.runtime(for: runtimeID)?.title ?? runtimeID)
                }
                if self.isActiveInterruptionGeneration(generationID),
                   let error {
                    self.recordSynthesisFailure(
                        error,
                        text: segment,
                        outputURL: tempURL,
                        voiceID: voiceID,
                        languageHint: nil,
                        context: "preview"
                    )
                }
                NSLog(
                    "LeafReader TTS preview: generation failed runtime=%@ voice=%@ speed=%@ textLength=%d output=%@ error=%@",
                    runtimeID,
                    voiceID,
                    speedID,
                    segment.count,
                    tempURL.path,
                    error?.localizedDescription ?? "unknown"
                )
                try? FileManager.default.removeItem(at: tempURL)
                DispatchQueue.main.async {
                    guard self.activeInterruptionGenerationID == generationID else { return }
                    callbacks.complete(false)
                }
                return
            }
            try? FileManager.default.removeItem(at: cacheURL)
            do {
                try FileManager.default.moveItem(at: tempURL, to: cacheURL)
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                DispatchQueue.main.async {
                    guard self.activeInterruptionGenerationID == generationID else { return }
                    callbacks.complete(false)
                }
                return
            }
            NSLog("LeafReader TTS preview: generated runtime=%@ voice=%@ speed=%@ output=%@", runtimeID, voiceID, speedID, cacheURL.path)
            DispatchQueue.main.async {
                guard self.activeInterruptionGenerationID == generationID else { return }
                callbacks.complete(true)
                self.playInterruptionOutput(cacheURL, removeAfterPlayback: false, callbacks: callbacks)
            }
        }
    }

    @MainActor
    func speakCachedVocabularyText(
        _ text: String,
        options: SynthesisOptions = .default,
        completion: @escaping (Bool) -> Void,
        finished: @escaping () -> Void
    ) {
        let callbacks = SpeechInterruptionCallbacks(completion: completion, finished: finished)
        cancelScheduledIdleShutdown()
        let value = SpeechTextPolicy.normalizedReadAloudInput(text)
        guard SpeechTextPolicy.isLocalTTSCandidate(value) else {
            callbacks.complete(false)
            return
        }

        let segment = SpeechTextPolicy.segments(for: value).joined(separator: " ")
        let synthesisRuntime = SpeechSynthesisRuntime.selected(for: segment)
        guard let runtime = synthesisRuntime.runtime else {
            callbacks.complete(false)
            return
        }
        let voiceID = vocabularyCacheVoiceID(runtime: runtime, text: segment)
        let cacheEntry = VocabularyAudioCache.entry(
            text: segment,
            runtimeID: runtime.id,
            voiceID: voiceID,
            speedID: options.cacheSpeedID
        )
        let languageHint = SpeechTextPolicy.prefersChineseTTS(segment)
            ? AISettingsStore.SpeechLanguageHint.chinese
            : nil
        let generationID = UUID()
        beginInterruptionGeneration(generationID)
        queue.async { [weak self] in
            guard let self else { return }
            guard self.isActiveInterruptionGeneration(generationID) else { return }
            if TTSWaveFile.isUsable(at: cacheEntry.url) {
                VocabularyAudioCache.markAccessed(cacheEntry.url)
                NSLog(
                    "LeafReader vocabulary audio cache: hit runtime=%@ voice=%@ speed=%@ key=%@ output=%@",
                    runtime.id,
                    voiceID,
                    options.cacheSpeedID,
                    cacheEntry.key,
                    cacheEntry.url.path
                )
                DispatchQueue.main.async {
                    guard self.activeInterruptionGenerationID == generationID else { return }
                    callbacks.complete(true)
                    self.playInterruptionOutput(cacheEntry.url, removeAfterPlayback: false, callbacks: callbacks)
                }
                return
            }

            try? FileManager.default.createDirectory(
                at: cacheEntry.url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let tempURL = cacheEntry.url.deletingLastPathComponent()
                .appendingPathComponent("pending-\(UUID().uuidString).wav")
            let result = self.generateWAVResult(
                text: segment,
                outputURL: tempURL,
                voiceID: voiceID,
                languageHint: languageHint,
                options: options,
                recordFailure: false
            )
            guard result.isSuccess,
                  TTSWaveFile.isUsable(at: tempURL),
                  VocabularyAudioCache.store(tempURL: tempURL, to: cacheEntry.url) else {
                try? FileManager.default.removeItem(at: tempURL)
                if self.isActiveInterruptionGeneration(generationID),
                   case .failure(let error) = result {
                    self.recordSynthesisFailure(
                        error,
                        text: segment,
                        outputURL: tempURL,
                        voiceID: voiceID,
                        languageHint: languageHint,
                        context: "vocabulary"
                    )
                }
                DispatchQueue.main.async {
                    guard self.activeInterruptionGenerationID == generationID else { return }
                    callbacks.complete(false)
                }
                return
            }
            NSLog(
                "LeafReader vocabulary audio cache: generated runtime=%@ voice=%@ speed=%@ key=%@ output=%@",
                runtime.id,
                voiceID,
                options.cacheSpeedID,
                cacheEntry.key,
                cacheEntry.url.path
            )
            DispatchQueue.main.async {
                guard self.activeInterruptionGenerationID == generationID else { return }
                callbacks.complete(true)
                self.playInterruptionOutput(cacheEntry.url, removeAfterPlayback: false, callbacks: callbacks)
            }
        }
    }

    @MainActor
    func cancelCurrentSpeechPreview(terminateKokoroWorker: Bool = false) {
        beginInterruptionGeneration(UUID())
        guard terminateKokoroWorker else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.runtimeAdapters.kokoro.stop()
            if self.activeRuntime == .kokoroCoreML {
                self.activeRuntime = nil
            }
        }
    }

    func stopInterruptionPlayback() {
        interruptionWatchdogWorkItem?.cancel()
        interruptionWatchdogWorkItem = nil
        interruptionCallbacks = nil
        interruptionPlayer?.delegate = nil
        interruptionPlayer?.stop()
        clearInterruptionPlayback()
    }

    func finishInterruptionPlayback() {
        interruptionWatchdogWorkItem?.cancel()
        interruptionWatchdogWorkItem = nil
        let callbacks = interruptionCallbacks
        interruptionCallbacks = nil
        clearInterruptionPlayback()
        if let callbacks {
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    callbacks.finish()
                }
            } else {
                Task { @MainActor in
                    callbacks.finish()
                }
            }
        }
    }

    @MainActor
    private func playInterruptionOutput(
        _ outputURL: URL,
        removeAfterPlayback: Bool = true,
        callbacks: SpeechInterruptionCallbacks
    ) {
        stopInterruptionPlayback()
        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(contentsOf: outputURL)
        } catch {
            NSLog("LeafReader SpeechPlayback: interruption AVAudioPlayer load failed (output=%@, error=%@)", outputURL.path, String(describing: error))
            try? FileManager.default.removeItem(at: outputURL)
            callbacks.finish()
            return
        }
        interruptionPlayer = player
        interruptionOutputURL = outputURL
        interruptionOutputShouldRemove = removeAfterPlayback
        interruptionCallbacks = callbacks
        player.delegate = self
        player.prepareToPlay()
        if !player.play() {
            NSLog("LeafReader SpeechPlayback: interruption AVAudioPlayer playback failed (output=%@)", outputURL.path)
            finishInterruptionPlayback()
        } else {
            NSLog("LeafReader TTS preview: playback started duration=%.3f output=%@", player.duration, outputURL.path)
            scheduleInterruptionWatchdog(for: player, outputURL: outputURL)
        }
    }

    @MainActor
    private func scheduleInterruptionWatchdog(for player: AVAudioPlayer, outputURL: URL) {
        interruptionWatchdogWorkItem?.cancel()
        let timeout = max(2.0, player.duration + 1.5)
        let workItem = DispatchWorkItem { [weak self, weak player] in
            guard let self,
                  let player,
                  self.interruptionPlayer === player else {
                return
            }
            NSLog("LeafReader SpeechPlayback: interruption playback watchdog advanced stuck sound (output=%@)", outputURL.path)
            player.stop()
            self.finishInterruptionPlayback()
        }
        interruptionWatchdogWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    private func clearInterruptionPlayback() {
        interruptionPlayer?.delegate = nil
        interruptionPlayer = nil
        if interruptionOutputShouldRemove, let interruptionOutputURL {
            try? FileManager.default.removeItem(at: interruptionOutputURL)
        }
        interruptionOutputShouldRemove = true
        interruptionOutputURL = nil
    }

    private func beginInterruptionGeneration(_ generationID: UUID) {
        let work = {
            self.activeInterruptionGenerationID = generationID
            self.stopInterruptionPlayback()
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }

    private func isActiveInterruptionGeneration(_ generationID: UUID) -> Bool {
        var active = false
        DispatchQueue.main.sync {
            active = self.activeInterruptionGenerationID == generationID
        }
        return active
    }

    private func vocabularyCacheVoiceID(runtime: SpeechRuntimeResourceManager.Runtime, text: String) -> String {
        if runtime == .kokoro {
            let languageHint: AISettingsStore.SpeechLanguageHint = SpeechTextPolicy.prefersChineseTTS(text) ? .chinese : .english
            return AISettingsStore.selectedKokoroSpeechVoiceID(languageHint: languageHint)
        }
        return AISettingsStore.selectedSpeechVoiceID(runtimeID: runtime.id)
    }
}

/// Carries UI-owned callbacks across the synthesis queue without claiming that
/// arbitrary caller closures are thread-safe. It is invoked only by main-actor
/// playback code after background synthesis has completed.
@MainActor
final class SpeechInterruptionCallbacks {
    private let completion: (Bool) -> Void
    private let finished: () -> Void

    init(completion: @escaping (Bool) -> Void, finished: @escaping () -> Void) {
        self.completion = completion
        self.finished = finished
    }

    func complete(_ usedLocalTTS: Bool) {
        completion(usedLocalTTS)
    }

    func finish() {
        finished()
    }
}
