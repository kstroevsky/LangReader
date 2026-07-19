import AVFoundation
import Cocoa

extension ReaderWindowController {
    @objc func toggleReadAloudFromToolbar() {
        guard !isReadAloudLoading else { return }
        if isReadAloudPaused {
            resumeReadAloudFromToolbar()
        } else if isReadAloudActive {
            pauseReadAloudFromToolbar()
        } else {
            startReadAloudFromToolbar()
        }
    }

    @objc func stopReadAloudFromToolbarAction() {
        stopReadAloudImmediately()
    }

    func startReadAloudFromToolbar() {
        guard canStartReadAloudWithLocalTTS() else { return }
        SpeechPlaybackCoordinator.shared.setManualAdvanceEnabled(readAloudAdvanceMode == .manual)
        guard currentDocumentKind == .pdf else {
            startWebReadAloudFromToolbar()
            return
        }
        beginReadAloudLoading()
        readCurrentPDFPageRemainderAndContinue(startAtPageTop: false)
    }

    func pauseReadAloudFromToolbar() {
        guard isReadAloudActive else { return }
        readAloudState.pausePlayback()
        SpeechPlaybackCoordinator.shared.pauseSpeaking()
        vocabularySpeechSynthesizer.pauseSpeaking(at: AVSpeechBoundary.immediate)
        updateReadAloudButton()
    }

    func resumeReadAloudFromToolbar() {
        guard isReadAloudActive else { return }
        readAloudState.resumePlayback()
        SpeechPlaybackCoordinator.shared.resumeSpeaking()
        vocabularySpeechSynthesizer.continueSpeaking()
        updateReadAloudButton()
        resumePendingReadAloudIfNeeded(trigger: .userAdvance)
    }

    func stopReadAloudImmediately() {
        resetReadAloudPlaybackState()
        SpeechPlaybackCoordinator.shared.stopSpeaking()
        vocabularySpeechSynthesizer.stopSpeaking(at: AVSpeechBoundary.immediate)
        resetReadAloudTracking()
        clearTemporaryReadAloudUnderline()
    }

    func finishReadAloudFromToolbar() {
        resetReadAloudPlaybackState()
        resetReadAloudTracking()
        restoreTitleAfterSpeechPlayback()
    }

    func beginReadAloudLoading() {
        readAloudState.beginLoading()
        clearUserSelectionForReadAloudStart()
        updateReadAloudButton()
    }

    func handleReadAloudStartResult(didUseLocalTTS: Bool) {
        readAloudState.markPlaying()
        updateReadAloudButton()
        guard !didUseLocalTTS else { return }
        finishReadAloudFromToolbar()
        if SpeechRuntimeResourceManager.runnableRuntime(preferredID: AISettingsStore.selectedSpeechRuntimeID) == nil {
            showMissingSpeechRuntimeAlert()
        } else if let error = SpeechPlaybackCoordinator.shared.consumeLastSynthesisError() {
            showSpeechPlaybackFailureAlert(error: error)
        } else {
            showSpeechPlaybackFailureAlert()
        }
    }

    func replayCurrentReadAloudSegment() {
        guard isReadAloudActive, !isReadAloudLoading else { return }
        focusReadAloudSegment(.current)
        readAloudState.resumePlayback()
        updateReadAloudButton()
        SpeechPlaybackCoordinator.shared.replayCurrentSegment()
    }

    func advanceReadAloudSegment() {
        guard isReadAloudActive, !isReadAloudLoading else { return }
        focusReadAloudSegment(.next)
        readAloudState.resumePlayback()
        updateReadAloudButton()
        if resumePendingReadAloudFromFloatingAdvanceIfNeeded() {
            return
        }
        if !SpeechPlaybackCoordinator.shared.hasActiveReadAloudWork() {
            resumePendingReadAloudIfNeeded(trigger: .userAdvance)
            return
        }
        SpeechPlaybackCoordinator.shared.advanceToNextSegment()
    }

    func replayPreviousReadAloudSegment() {
        guard isReadAloudActive, !isReadAloudLoading, canReadAloudGoPrevious else { return }
        focusReadAloudSegment(.previous)
        readAloudState.resumePlayback()
        updateReadAloudButton()
        SpeechPlaybackCoordinator.shared.replayPreviousSegment()
    }

    func toggleReadAloudAdvanceMode() {
        readAloudAdvanceMode = readAloudAdvanceMode.toggled
        readAloudAdvanceMode.save()
        SpeechPlaybackCoordinator.shared.setManualAdvanceEnabled(readAloudAdvanceMode == .manual)
        if readAloudAdvanceMode == .automatic, isReadAloudPaused {
            readAloudState.resumePlayback()
            resumePendingReadAloudIfNeeded()
        }
        updateReadAloudButton()
        updateReadAloudFloatingControl()
    }

    func pauseReadAloudForManualAdvance() {
        guard readAloudAdvanceMode == .manual else { return }
        readAloudState.pausePlayback()
        updateReadAloudButton()
    }

    func deferReadAloudContinuationIfNeeded(
        trigger: ReadAloudContinuationTrigger,
        setPending: () -> Void
    ) -> Bool {
        if readAloudAdvanceMode == .manual, trigger == .automatic {
            setPending()
            pauseReadAloudForManualAdvance()
            return true
        }
        guard !isReadAloudPaused else {
            setPending()
            return true
        }
        return false
    }

    private func resumePendingReadAloudIfNeeded(trigger: ReadAloudContinuationTrigger = .automatic) {
        resumePendingPDFReadAloudIfNeeded(trigger: trigger)
        resumePendingWebReadAloudIfNeeded(trigger: trigger)
    }

    private func resumePendingReadAloudFromFloatingAdvanceIfNeeded() -> Bool {
        if currentDocumentKind == .pdf, pendingReadAloudPDFContinuation != nil {
            SpeechPlaybackCoordinator.shared.stopSpeaking()
            resumePendingPDFReadAloudIfNeeded(trigger: .userAdvance)
            return true
        }
        if currentDocumentKind != .pdf, pendingReadAloudWebContinuation {
            SpeechPlaybackCoordinator.shared.stopSpeaking()
            resumePendingWebReadAloudIfNeeded(trigger: .userAdvance)
            return true
        }
        return false
    }

    private func focusReadAloudSegment(_ target: SpeechPlaybackCoordinator.ReadAloudNavigationTarget) {
        guard let segment = SpeechPlaybackCoordinator.shared.readAloudSegment(for: target) else { return }
        focusReadAloudSegment(segment)
    }

    private func clearUserSelectionForReadAloudStart() {
        clearPDFSelectionState()
        pdfView.clearSelection()
        guard currentDocumentKind != .pdf, webView?.isHidden == false else { return }
        webView?.evaluateJavaScript("""
        (() => {
          if (window.leafReaderClearSelectionVisualOnly) {
            window.leafReaderClearSelectionVisualOnly();
          } else {
            const selection = window.getSelection && window.getSelection();
            if (selection) selection.removeAllRanges();
          }
        })();
        """)
    }

    private func resetReadAloudPlaybackState() {
        readAloudState.stopPlayback()
        updateReadAloudButton()
    }

    private func resetReadAloudTracking() {
        resetReadAloudPDFProgress()
        lastReadAloudAISource = nil
        lastReadAloudLinkedWordID = nil
        lastReadAloudSoftHintKey = nil
        dismissReadAloudSoftHint()
        pendingReadAloudPDFContinuation = nil
        pendingReadAloudWebContinuation = false
    }

    func updateReadAloudButton() {
        guard let readAloudButton else { return }
        let symbolName = isReadAloudLoading
            ? "hourglass"
            : (isReadAloudPaused ? "play.fill" : (isReadAloudActive ? "pause.fill" : "speaker.wave.2"))
        readAloudButton.title = isReadAloudLoading
            ? AppText.localized("加载中", "Loading")
            : (isReadAloudPaused
            ? AppText.localized("继续", "Resume")
            : (isReadAloudActive ? AppText.localized("暂停", "Pause") : AppText.localized("朗读", "Read")))
        readAloudButton.isEnabled = !isReadAloudLoading
        setCapsuleButtonSymbol(symbolName, on: readAloudButton, accessibilityDescription: readAloudButton.title)
        readAloudButton.toolTip = isReadAloudLoading
            ? AppText.localized("正在加载朗读模型", "Loading read aloud model")
            : (isReadAloudPaused
            ? AppText.localized("继续朗读", "Resume reading")
            : (isReadAloudActive
                ? AppText.localized("暂停朗读", "Pause reading")
                : AppText.localized("从当前屏幕顶部开始朗读", "Read from the top of the current screen")))
        readAloudStopButton?.isHidden = !isReadAloudActive
        readAloudButton.needsDisplay = true
        readAloudButton.displayIfNeeded()
        updateReadAloudFloatingControl()
    }
}
