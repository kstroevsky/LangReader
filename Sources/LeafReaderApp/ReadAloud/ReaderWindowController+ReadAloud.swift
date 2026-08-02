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
        // Runs only once the toolbar exists; the SwiftUI Read button derives its
        // title, symbol and tooltip from these three flags via `ReaderTopBarTitles`.
        guard toolbarView != nil else { return }
        topBarModel.readAloudActive = isReadAloudActive
        topBarModel.readAloudPaused = isReadAloudPaused
        topBarModel.readAloudLoading = isReadAloudLoading
        refreshChromeState()
        updateReadAloudFloatingControl()
    }
}
