import AVFoundation
import Cocoa
import LeafReaderCore

extension AIChatPanel {
    func isVocabularySelection(_ text: String) -> Bool {
        VocabularyTextPolicy.isVocabularySelection(text)
    }

    func shouldUseDefinitionProvider(
        for text: String,
        routingContext: VocabularyDefinitionRoutingContext?
    ) -> Bool {
        VocabularyTextPolicy.isSingleVocabularyWord(text) && routingContext?.provider != nil
    }

    func contextForWordQuestion(text: String) -> String {
        onAskSelectedText?(text) ?? ""
    }

    func handleDefinitionQuestion(
        _ text: String,
        routingContext: VocabularyDefinitionRoutingContext?
    ) -> Bool {
        guard let routingContext,
              let provider = routingContext.provider,
              shouldUseDefinitionProvider(for: text, routingContext: routingContext) else {
            return false
        }
        speakSelectedWordIfNeeded(text)
        let selectedContext = contextForWordQuestion(text: text)
        let displayedQuestion = vocabularyBubbleTitle(for: text)
        resetTranscript()
        appendBubble(role: AppText.userRole, text: displayedQuestion, collapsible: false)
        recordTranscript(role: AppText.userRole, text: displayedQuestion)
        clearSelectedText()
        setBusy(true, text: AppText.localized("正在查词典...", "Looking up dictionary..."))

        Task { @MainActor [weak self] in
            let result: Result<VocabularyDefinition?, Error>
            do {
                result = .success(try await provider.definition(for: VocabularyDefinitionRequest(
                    language: routingContext.language,
                    lemma: text,
                    surfaceForm: text,
                    context: selectedContext
                )))
            } catch {
                result = .failure(error)
            }
            guard let self else { return }
            self.setBusy(false, text: "")
            guard self.isDefinitionRoutingContextCurrent(routingContext) else {
                self.resetTranscript()
                return
            }
            switch result {
            case .success(let definition?):
                self.persistGermanFlexionIfAvailable(
                    for: text,
                    routingContext: routingContext
                )
                self.appendMessage(ChatMessage(
                    role: "user",
                    content: self.wordPrompt(for: text, context: selectedContext)
                ))
                self.showFocusedWord(word: text, answer: definition.markdown, linkID: nil)
            case .success(nil), .failure:
                let message = AppText.localized(
                    "没有找到“\(text)”的兼容词典释义。",
                    "No compatible dictionary definition was found for “\(text)”."
                )
                self.appendBubble(role: AppText.errorRole, text: message, collapsible: false)
            }
        }
        return true
    }

    func isDefinitionRoutingContextCurrent(_ expected: VocabularyDefinitionRoutingContext) -> Bool {
        guard let current = onVocabularyDefinitionContextRequested?() else { return false }
        return current.isSemanticallyEqual(to: expected)
    }

    func isDefinitionRoutingIdentityCurrent(_ expected: VocabularyDefinitionRoutingIdentity) -> Bool {
        guard let current = onVocabularyDefinitionContextRequested?() else { return false }
        return current.identity == expected
    }

    private func persistGermanFlexionIfAvailable(
        for text: String,
        routingContext: VocabularyDefinitionRoutingContext
    ) {
        guard routingContext.providerDescriptor?.id == "dictionary.de-wiktionary",
              let entry = GermanWiktionaryDictionary.shared.cachedEntry(for: text) else {
            return
        }
        let flexion = StoredGermanFlexion(
            lemma: entry.lemma,
            genus: entry.flexion?.genus,
            auxiliary: entry.flexion?.auxiliary,
            forms: (entry.flexion?.forms ?? []).map {
                StoredGermanFlexionForm(
                    parameter: $0.label,
                    surface: $0.surface,
                    isVariant: $0.isVariant
                )
            },
            fetchedAt: Date()
        )
        GermanFlexionStore.shared.save(flexion)
        GermanFlexionStore.shared.regroupSavedVocabulary(for: flexion)
    }

    func scrollToDictionaryAnswer(_ body: NSTextField) {
        guard let box = body.superview else { return }
        DispatchQueue.main.async { [weak self, weak box] in
            guard let self, let box else { return }
            self.scrollTranscriptToTop(of: box)
        }
    }

    func speakSelectedWordIfNeeded(_ text: String) {
        guard AISettingsStore.speakSelectedWordEnabled,
              VocabularyTextPolicy.isSingleVocabularyWord(text) else {
            return
        }
        speakWord(text)
    }

    func speakWord(_ text: String) {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        if VocabularyTextPolicy.shouldUseSystemTTSForShortSelection(text) {
            speechSynthesizer.speak(SpeechUtteranceFactory.utterance(for: text))
            return
        }
        SpeechPlaybackCoordinator.shared.speakText(text) { [weak self] didUseLocalTTS in
            guard !didUseLocalTTS else { return }
            self?.speechSynthesizer.speak(SpeechUtteranceFactory.utterance(for: text))
        }
    }

    func wordPrompt(for word: String, context: String) -> String {
        AIPromptStore.wordPrompt(for: word, context: context)
    }

    func sentencePrompt(for text: String) -> String {
        AIPromptStore.sentencePrompt(for: text)
    }
}
