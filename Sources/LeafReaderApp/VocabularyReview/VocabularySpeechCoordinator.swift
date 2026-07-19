import AVFoundation
import Cocoa

protocol VocabularySpeechCoordinatorOwner: AnyObject {
    var shouldResumeReadAloudAfterVocabularySpeech: Bool { get }
    var vocabularySpeechLanguageCode: String? { get }

    func prepareForVocabularySpeechStart()
    func pauseReadAloudForVocabularySpeech()
    func resumeReadAloudAfterVocabularySpeech(shouldResume: Bool)
    func clearReaderSelectionForVocabularySpeech()
}

final class VocabularySpeechCoordinator: NSObject, AVSpeechSynthesizerDelegate {
    private weak var owner: VocabularySpeechCoordinatorOwner?
    private let synthesizer: AVSpeechSynthesizer
    private var selectionSpeechCompletion: (() -> Void)?
    private var shouldClearSelectionOnSpeechStart = false

    init(synthesizer: AVSpeechSynthesizer, owner: VocabularySpeechCoordinatorOwner) {
        self.synthesizer = synthesizer
        self.owner = owner
        super.init()
        synthesizer.delegate = self
    }

    func speak(
        _ texts: [String],
        options: SpeechPlaybackCoordinator.SynthesisOptions = .default
    ) {
        let playableTexts = texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !playableTexts.isEmpty else { return }

        owner?.prepareForVocabularySpeechStart()
        shouldClearSelectionOnSpeechStart = true
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: AVSpeechBoundary.immediate)
        }

        if playableTexts.count == 1, let text = playableTexts.first {
            speakSingleText(text, options: options)
            return
        }

        selectionSpeechCompletion = nil
        for text in playableTexts {
            synthesizer.speak(
                SpeechUtteranceFactory.utterance(
                    for: text,
                    languageCode: preferredLanguageCode(for: text)
                )
            )
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        clearSelectionForSpeechStartIfNeeded()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if let completion = selectionSpeechCompletion {
            selectionSpeechCompletion = nil
            completion()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        shouldClearSelectionOnSpeechStart = false
        selectionSpeechCompletion = nil
    }

    private func speakSingleText(
        _ text: String,
        options: SpeechPlaybackCoordinator.SynthesisOptions
    ) {
        let languageCode = preferredLanguageCode(for: text)
        // Short selections stay on AVSpeechSynthesizer so they can interrupt read-aloud cheaply.
        // Longer German vocabulary/context speech also uses macOS because the bundled
        // local engines currently provide English and Chinese voices only.
        if VocabularyTextPolicy.shouldUseSystemTTSForShortSelection(text)
            || languageCode?.hasPrefix("de") == true {
            selectionSpeechCompletion = nil
            synthesizer.speak(SpeechUtteranceFactory.utterance(for: text, languageCode: languageCode))
            return
        }

        let shouldResumeReadAloud = owner?.shouldResumeReadAloudAfterVocabularySpeech ?? false
        if shouldResumeReadAloud {
            // Vocabulary playback is an interruption: pause the main read-aloud stream,
            // then resume only if it was active at the time this request started.
            owner?.pauseReadAloudForVocabularySpeech()
            SpeechPlaybackCoordinator.shared.speakCachedVocabularyText(text, options: options) { [weak self] didUseLocalTTS in
                guard let self else { return }
                guard !didUseLocalTTS else {
                    self.clearSelectionForSpeechStartIfNeeded()
                    return
                }
                DispatchQueue.main.async {
                    self.speakWithAppleTTS(text, languageCode: languageCode) { [weak self] in
                        self?.owner?.resumeReadAloudAfterVocabularySpeech(shouldResume: shouldResumeReadAloud)
                    }
                }
            } finished: { [weak self] in
                DispatchQueue.main.async {
                    self?.owner?.resumeReadAloudAfterVocabularySpeech(shouldResume: shouldResumeReadAloud)
                }
            }
            return
        }

        SpeechPlaybackCoordinator.shared.speakCachedVocabularyText(text, options: options) { [weak self] didUseLocalTTS in
            guard let self else { return }
                guard !didUseLocalTTS else {
                    self.clearSelectionForSpeechStartIfNeeded()
                    return
                }
            self.synthesizer.speak(SpeechUtteranceFactory.utterance(for: text, languageCode: languageCode))
        } finished: {
        }
    }

    private func speakWithAppleTTS(
        _ text: String,
        languageCode: String?,
        finished: @escaping () -> Void
    ) {
        selectionSpeechCompletion = finished
        synthesizer.stopSpeaking(at: AVSpeechBoundary.immediate)
        synthesizer.speak(SpeechUtteranceFactory.utterance(for: text, languageCode: languageCode))
    }

    private func preferredLanguageCode(for text: String) -> String? {
        let selectedTextLanguage = SpeechTextPolicy.systemSpeechLanguageCode(for: text)
        if selectedTextLanguage != "en-US" {
            return selectedTextLanguage
        }
        return owner?.vocabularySpeechLanguageCode ?? selectedTextLanguage
    }

    private func clearSelectionForSpeechStartIfNeeded() {
        guard shouldClearSelectionOnSpeechStart else { return }
        shouldClearSelectionOnSpeechStart = false
        owner?.clearReaderSelectionForVocabularySpeech()
    }
}
