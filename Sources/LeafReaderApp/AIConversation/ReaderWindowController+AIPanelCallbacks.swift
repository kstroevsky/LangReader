extension ReaderWindowController {
    func configureAIPanelCallbacks() {
        configureAIPanelResizeCallbacks()
        configureAIPanelContentCallbacks()
        configureAIPanelVocabularyCallbacks()
        configureAIPanelConversationCallbacks()
        configureSelectionToolbarCallbacks()
    }

    private func configureAIPanelResizeCallbacks() {
        resizeHandle.onDragDeltaX = { [weak self] deltaX in
            self?.resizeAIPanel(deltaX: deltaX)
        }
        resizeHandle.onDragEnded = { [weak self] in
            self?.finishAIPanelResize()
        }
    }

    private func configureAIPanelContentCallbacks() {
        aiPanel.onAskSelectedText = { [weak self] text in
            guard let self else { return nil }
            return self.contextForCurrentSelection(selectedText: text)
        }
        aiPanel.onSummarizeCurrentContent = { [weak self] completion in
            self?.currentSummaryContent(completion: completion)
        }
        aiPanel.onTranslateCurrentContent = { [weak self] completion in
            self?.currentTranslationContent(completion: completion)
        }
        aiPanel.onCurrentReadingContent = { [weak self] completion in
            self?.currentReadingQuestionContent(completion: completion)
        }
        aiPanel.onDocumentQuestionPrompt = { [weak self] request, completion in
            self?.documentAgentPrompt(
                question: request.question,
                questionSubject: request.questionSubject,
                context: request.context,
                completion: completion
            )
        }
        aiPanel.onDocumentQuestionCancelled = { [weak self] in
            self?.cancelDocumentAgentPrompt()
        }
        aiPanel.onSettingsRequired = { [weak self] in
            self?.openModelSettings()
        }
    }

    private func configureAIPanelVocabularyCallbacks() {
        aiPanel.onSelectedWordQuestionStarted = { [weak self] request in
            guard let self else { return nil }
            if self.currentDocumentKind == .pdf {
                return self.persistSelectedWordIfNeeded(
                    self.pdfView.currentSelection,
                    text: request.text,
                    context: request.selectedContext
                )
            }
            return self.persistSelectedWebWordIfNeeded(text: request.text, context: request.selectedContext)
        }
        aiPanel.onLinkedAnswerCompleted = { [weak self] linkID, question, answer in
            self?.updateStoredLinkedWordAnswer(linkID: linkID, question: question, answer: answer)
        }
        aiPanel.onLinkedAnswerFailed = { [weak self] linkID in
            self?.discardPendingLinkedWord(linkID: linkID)
        }
        aiPanel.onLinkedWordAnswerAvailable = { [weak self] linkID in
            self?.linkedWordAnswer(for: linkID)
        }
        aiPanel.onLinkedBubbleSelected = { [weak self] linkID in
            self?.jumpToStoredLinkedWord(linkID: linkID)
        }
        aiPanel.onLinkedBubbleDeleted = { [weak self] linkID in
            self?.removeVocabularyRecords(ids: [linkID])
        }
        aiPanel.onOccurrencesRequested = { [weak self] word in
            self?.openWordsWindow(focusingWord: word)
        }
        aiPanel.onWordFocusInfoRequested = { [weak self] word in
            self?.wordFocusInfo(for: word)
        }
    }

    private func configureAIPanelConversationCallbacks() {
        aiPanel.onConversationChanged = { [weak self] conversation in
            self?.saveAIConversationIfNeeded(conversation)
        }
        aiPanel.onConversationBubblesDeleted = { [weak self] deletedBubbles in
            self?.removeAIConversationBubblesFromPersistence(deletedBubbles)
        }
        aiPanel.onConversationSourcesChanged = { [weak self] sources in
            self?.reconcileAISourceUnderlines(activeSources: sources)
        }
        aiPanel.onCurrentSourceLocation = { [weak self] in
            self?.currentAIConversationSourceLocation()
        }
        aiPanel.onConversationBubbleSelected = { [weak self] sourceLocation in
            self?.jumpToAIConversationSource(sourceLocation)
        }
        aiPanel.onNonFollowUpSelectionInteraction = { [weak self] in
            self?.clearReaderSelectionForBubbleSelection()
        }
    }

    private func configureSelectionToolbarCallbacks() {
        selectionActionToolbar.onTranslate = { [weak self] in
            self?.runSelectionToolbarAction(.translate)
        }
        selectionActionToolbar.onExplain = { [weak self] in
            self?.runSelectionToolbarAction(.explain)
        }
        selectionActionToolbar.onDifficultSentence = { [weak self] in
            self?.runSelectionToolbarAction(.difficultSentence)
        }
        selectionActionToolbar.onAddWord = { [weak self] in
            self?.runSelectionToolbarAction(.addWord)
        }
        selectionActionToolbar.onSaveWord = { [weak self] in
            self?.runSelectionToolbarAction(.saveWord)
        }
        selectionActionToolbar.onSummarize = { [weak self] in
            self?.runSelectionToolbarAction(.summarize)
        }
        selectionActionToolbar.onSpeak = { [weak self] in
            self?.runSelectionToolbarAction(.speak)
        }
        selectionActionToolbar.onNote = { [weak self] in
            self?.runSelectionToolbarAction(.note)
        }
        selectionActionToolbar.onCopy = { [weak self] in
            self?.runSelectionToolbarAction(.copy)
        }
        selectionActionToolbar.onConfigureModel = { [weak self] in
            self?.runSelectionToolbarAction(.configureModel)
        }
    }
}
