import AVFoundation
import Cocoa

extension AIChatPanel {
    func isVocabularySelection(_ text: String) -> Bool {
        VocabularyTextPolicy.isVocabularySelection(text)
    }

    func shouldUseLocalDictionary(for text: String) -> Bool {
        isSingleEnglishWord(text)
    }

    func startWordQuestionIfNeeded(text: String) -> WordQuestionStartResult? {
        guard isVocabularySelection(text) else { return nil }
        return onSelectedWordQuestionStarted?(WordQuestionRequest(text: text, selectedContext: nil))
    }

    func contextForWordQuestion(text: String, start: WordQuestionStartResult?) -> String {
        start?.selectedContext ?? onAskSelectedText?(text) ?? ""
    }

    func handleLocalDictionaryQuestion(_ text: String) -> Bool {
        guard shouldUseLocalDictionary(for: text) else { return false }
        speakSelectedWordIfNeeded(text)
        let answerRequest = AnswerProviderRequest(text: text, context: "", linkID: nil)
        guard let initialAnswer = localOnlyAnswerProvider().answer(for: answerRequest)?.answer else {
            return false
        }

        let wordStart = startWordQuestionIfNeeded(text: text)
        let linkID = wordStart?.linkID
        if let linkID, hasLinkedBubble(id: linkID) {
            clearSelectedText()
            scrollToLinkedBubble(id: linkID)
            return true
        }
        let selectedContext = contextForWordQuestion(text: text, start: wordStart)
        let answer = localOnlyAnswerProvider()
            .answer(for: AnswerProviderRequest(text: text, context: selectedContext, linkID: linkID))?
            .answer ?? initialAnswer
        let displayedQuestion = vocabularyBubbleTitle(for: text)
        appendBubble(role: AppText.userRole, text: displayedQuestion, collapsible: true, linkID: linkID)
        recordTranscript(role: AppText.userRole, text: displayedQuestion, linkID: linkID)
        let answerBody = appendBubble(role: AppText.aiRole, text: answer, collapsible: false, renderMarkdown: true, linkID: linkID)
        recordTranscript(role: AppText.aiRole, text: answer, linkID: linkID)
        appendMessage(ChatMessage(role: "user", content: wordPrompt(for: text, context: selectedContext), linkID: linkID))
        appendMessage(ChatMessage(role: "assistant", content: answer, linkID: linkID))
        if let linkID {
            onLinkedAnswerCompleted?(linkID, displayedQuestion, answer)
        }
        scrollToDictionaryAnswer(answerBody)
        clearSelectedText()
        return true
    }

    func handleGermanDictionaryQuestion(_ text: String) -> Bool {
        guard isSingleEnglishWord(text), NetworkConnectivityMonitor.shared.isOnline else {
            return false
        }
        speakSelectedWordIfNeeded(text)
        let wordStart = startWordQuestionIfNeeded(text: text)
        let linkID = wordStart?.linkID
        let selectedContext = contextForWordQuestion(text: text, start: wordStart)
        let displayedQuestion = vocabularyBubbleTitle(for: text)
        // Focus on this one word: clear whatever the transcript held so the
        // lookup does not append to a list of other words.
        resetTranscript()
        appendBubble(role: AppText.userRole, text: displayedQuestion, collapsible: false, linkID: linkID)
        recordTranscript(role: AppText.userRole, text: displayedQuestion, linkID: linkID)
        clearSelectedText()
        setBusy(true, text: AppText.localized("正在查德语词典...", "Looking up German dictionary..."))

        GermanWiktionaryDictionary.shared.lookup(text) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.setBusy(false, text: "")
                switch result {
                case .success(let entry):
                    // Persist the flexion table as a side effect of the lookup
                    // the reader already asked for, so later encounters with
                    // any of that word's forms resolve offline.
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
                    // Learning the paradigm is the moment it becomes possible to
                    // tell that a word saved as an inflected form belongs to
                    // this lemma, so re-file it now rather than leaving the
                    // entry stranded under its own spelling.
                    GermanFlexionStore.shared.regroupSavedVocabulary(for: flexion)
                    let answer = entry.markdown
                    // The prompt is recorded first so the answer's follow-up
                    // context is intact, then the focused view replaces the
                    // loading bubble with the header + definition for this word.
                    self.appendMessage(ChatMessage(role: "user", content: self.wordPrompt(for: text, context: selectedContext), linkID: linkID))
                    self.showFocusedWord(word: text, answer: answer, linkID: linkID)
                    if let linkID {
                        self.onLinkedAnswerCompleted?(linkID, displayedQuestion, answer)
                    }
                case .failure:
                    let message = AppText.localized(
                        "Deutsch Wiktionary 中没有找到“\(text)”的词条。",
                        "No German Wiktionary entry was found for “\(text)”."
                    )
                    self.appendBubble(role: AppText.errorRole, text: message, collapsible: false)
                    if let linkID {
                        self.onLinkedAnswerFailed?(linkID)
                    }
                }
            }
        }
        return true
    }

    func scrollToDictionaryAnswer(_ body: NSTextField) {
        guard let box = body.superview else { return }
        DispatchQueue.main.async { [weak self, weak box] in
            guard let self, let box else { return }
            self.scrollTranscriptToTop(of: box)
        }
    }

    func isSingleEnglishWord(_ text: String) -> Bool {
        VocabularyTextPolicy.isSingleEnglishWord(text)
    }

    func speakSelectedWordIfNeeded(_ text: String) {
        guard AISettingsStore.speakSelectedWordEnabled,
              isSingleEnglishWord(text) else {
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
