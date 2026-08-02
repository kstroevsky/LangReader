import Cocoa
import PDFKit
import WebKit
import LeafReaderCore

extension ReaderWindowController {
    /// The async surface used by Reading Note editors.  The editor owns the
    /// returned task, and cancelling it only cancels this request ID.
    func documentAgentPrompt(
        question: String,
        questionSubject: String = "",
        context: String,
        showsEvidenceBubbles: Bool = true
    ) async -> String? {
        let requestID = beginDocumentAgentPrompt()
        return await withTaskCancellationHandler(operation: { [weak self] in
            guard let self else { return nil }
            return await withCheckedContinuation { continuation in
                self.aiState.documentPromptContinuations[requestID] = continuation
                self.startDocumentAgentPrompt(
                    question: question,
                    questionSubject: questionSubject,
                    context: context,
                    showsEvidenceBubbles: showsEvidenceBubbles,
                    requestID: requestID
                ) { [weak self] value in
                    self?.resumeDocumentAgentPrompt(requestID, value: value)
                }
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in
                self?.cancelDocumentAgentPrompt(requestID: requestID)
            }
        })
    }

    /// Callback compatibility for the existing AI chat panel.  It has a
    /// request ID too, so it no longer competes with note editors.
    func documentAgentPrompt(
        question: String,
        questionSubject: String = "",
        context: String,
        showsEvidenceBubbles: Bool = true,
        completion: @escaping (String?) -> Void
    ) {
        let requestID = beginDocumentAgentPrompt()
        startDocumentAgentPrompt(
            question: question,
            questionSubject: questionSubject,
            context: context,
            showsEvidenceBubbles: showsEvidenceBubbles,
            requestID: requestID,
            completion: completion
        )
    }

    private func startDocumentAgentPrompt(
        question: String,
        questionSubject: String,
        context: String,
        showsEvidenceBubbles: Bool,
        requestID: UUID,
        completion: @escaping (String?) -> Void
    ) {
        let finish: (String?) -> Void = { [weak self] value in
            guard let self, self.isDocumentAgentPromptActive(requestID) else { return }
            self.finishDocumentAgentPrompt(requestID)
            completion(value)
        }
        currentReadingContextSnapshot(preserveLineBreaks: true) { [weak self] snapshot in
            DispatchQueue.main.async {
                guard let self, self.isDocumentAgentPromptActive(requestID), let snapshot else {
                    finish(nil)
                    return
                }
                if self.currentDocumentKind == .pdf {
                    self.pdfDocumentAgentPrompt(
                        question: question,
                        questionSubject: questionSubject,
                        context: context,
                        showsEvidenceBubbles: showsEvidenceBubbles,
                        snapshot: snapshot,
                        requestID: requestID,
                        completion: finish
                    )
                    return
                }
                self.webDocumentAgentPrompt(
                    question: question,
                    questionSubject: questionSubject,
                    context: context,
                    showsEvidenceBubbles: showsEvidenceBubbles,
                    snapshot: snapshot,
                    requestID: requestID,
                    completion: finish
                )
            }
        }
    }

    func cancelDocumentAgentPrompt() {
        for requestID in aiState.activeDocumentPromptIDs {
            cancelDocumentAgentPrompt(requestID: requestID)
        }
    }

    func cancelDocumentAgentPrompt(requestID: UUID) {
        guard aiState.activeDocumentPromptIDs.remove(requestID) != nil else { return }
        aiState.retrievalQueryTasks.removeValue(forKey: requestID)?.cancel()
        aiState.documentPromptContinuations.removeValue(forKey: requestID)?.resume(returning: nil)
    }

    private func beginDocumentAgentPrompt() -> UUID {
        let requestID = UUID()
        aiState.activeDocumentPromptIDs.insert(requestID)
        return requestID
    }

    func isDocumentAgentPromptActive(_ requestID: UUID) -> Bool {
        aiState.activeDocumentPromptIDs.contains(requestID)
    }

    private func finishDocumentAgentPrompt(_ requestID: UUID) {
        aiState.activeDocumentPromptIDs.remove(requestID)
        aiState.retrievalQueryTasks.removeValue(forKey: requestID)?.cancel()
    }

    private func resumeDocumentAgentPrompt(_ requestID: UUID, value: String?) {
        guard isDocumentAgentPromptActive(requestID) else { return }
        finishDocumentAgentPrompt(requestID)
        aiState.documentPromptContinuations.removeValue(forKey: requestID)?.resume(returning: value)
    }

    func pdfDocumentAgentPrompt(
        question: String,
        questionSubject: String,
        context: String,
        showsEvidenceBubbles: Bool,
        snapshot: ReadingContextSnapshot,
        requestID: UUID,
        completion: @escaping (String?) -> Void
    ) {
        guard pdfView.document != nil else {
            completion(nil)
            return
        }

        let currentPageText = snapshot.visibleText
        let chapterText = snapshot.nearbyText
        let combinedContext = combinedReadingContext(base: context, snapshot: snapshot)
        ensureDocumentAgentIndexAsync { [weak self] in
            guard let self, self.isDocumentAgentPromptActive(requestID) else {
                completion(nil)
                return
            }
            self.crossLingualRetrievalQueryIfNeeded(question: question, currentPageText: currentPageText, requestID: requestID) { [weak self] retrievalQuery in
                DispatchQueue.main.async {
                    guard let self, self.isDocumentAgentPromptActive(requestID) else {
                        completion(nil)
                        return
                    }
                    let combinedRetrievalQuestion = [question, retrievalQuery]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n")
                    let retrievalQuestion = combinedRetrievalQuestion.isEmpty ? question : combinedRetrievalQuestion
                    let currentPageIndex = self.currentPageIndex()
                    self.preparePDFEmbeddingsIfPossible(priorityPageIndex: currentPageIndex) { [weak self] in
                        guard let self, self.isDocumentAgentPromptActive(requestID) else {
                            completion(nil)
                            return
                        }
                        self.queryEmbedding(for: retrievalQuestion) { [weak self] queryEmbedding in
                            DispatchQueue.main.async {
                                guard let self, self.isDocumentAgentPromptActive(requestID) else {
                                    completion(nil)
                                    return
                                }
                                let evidence = self.pdfAgentIndex?.search(
                                    question: retrievalQuestion,
                                    currentPageIndex: self.currentPageIndex(),
                                    queryEmbedding: queryEmbedding
                                ) ?? []
                                let searchResults = self.documentAgentSearchResults(
                                    from: evidence,
                                    showsEvidenceBubbles: showsEvidenceBubbles
                                )
                                completion(AIPromptStore.documentAgentPrompt(
                                    title: self.documentTitleForAI(),
                                    question: question,
                                    questionSubject: questionSubject,
                                    currentPageText: ReaderAIContextPolicy.prefix(currentPageText, limit: ReaderAIContextPolicy.documentAgentCurrentPageLimit),
                                    chapterText: ReaderAIContextPolicy.prefix(chapterText, limit: ReaderAIContextPolicy.documentAgentNearbyTextLimit),
                                    searchResults: searchResults,
                                    context: combinedContext
                                ))
                            }
                        }
                    }
                }
            }
        }
    }

    func webDocumentAgentPrompt(
        question: String,
        questionSubject: String,
        context: String,
        showsEvidenceBubbles: Bool,
        snapshot: ReadingContextSnapshot,
        requestID: UUID,
        completion: @escaping (String?) -> Void
    ) {
        let combinedContext = combinedReadingContext(base: context, snapshot: snapshot)
        ensureDocumentAgentIndexAsync { [weak self] in
            guard let self, self.isDocumentAgentPromptActive(requestID) else {
                completion(nil)
                return
            }
            self.crossLingualRetrievalQueryIfNeeded(question: question, currentPageText: snapshot.visibleText, requestID: requestID) { [weak self] retrievalQuery in
                DispatchQueue.main.async {
                    guard let self, self.isDocumentAgentPromptActive(requestID) else {
                        completion(nil)
                        return
                    }
                    let combinedRetrievalQuestion = [question, retrievalQuery]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n")
                    let retrievalQuestion = combinedRetrievalQuestion.isEmpty ? question : combinedRetrievalQuestion
                    let priorityIndex = self.currentEmbeddingPriorityIndex()
                    self.preparePDFEmbeddingsIfPossible(priorityPageIndex: priorityIndex) { [weak self] in
                        guard let self, self.isDocumentAgentPromptActive(requestID) else {
                            completion(nil)
                            return
                        }
                        self.queryEmbedding(for: retrievalQuestion) { [weak self] queryEmbedding in
                            DispatchQueue.main.async {
                                guard let self, self.isDocumentAgentPromptActive(requestID) else {
                                    completion(nil)
                                    return
                                }
                                let evidence = self.pdfAgentIndex?.search(
                                    question: retrievalQuestion,
                                    currentPageIndex: self.currentEmbeddingPriorityIndex(),
                                    queryEmbedding: queryEmbedding
                                ) ?? []
                                let searchResults = self.documentAgentSearchResults(
                                    from: evidence,
                                    showsEvidenceBubbles: showsEvidenceBubbles
                                )
                                completion(AIPromptStore.documentAgentPrompt(
                                    title: snapshot.title,
                                    question: question,
                                    questionSubject: questionSubject,
                                    currentPageText: ReaderAIContextPolicy.prefix(snapshot.visibleText, limit: ReaderAIContextPolicy.documentAgentCurrentPageLimit),
                                    chapterText: ReaderAIContextPolicy.prefix(snapshot.nearbyText, limit: ReaderAIContextPolicy.documentAgentNearbyTextLimit),
                                    searchResults: searchResults,
                                    context: combinedContext,
                                    currentTextTitle: AppText.localized("当前可见内容", "Current visible text"),
                                    nearbyTextTitle: AppText.localized("当前阅读位置附近内容", "Nearby reading text")
                                ))
                            }
                        }
                    }
                }
            }
        }
    }

    func documentAgentSearchResults(
        from evidence: [PDFDocumentAgentEvidence],
        showsEvidenceBubbles: Bool
    ) -> String {
        if showsEvidenceBubbles {
            appendEvidenceBubbles(evidence)
        }
        let evidenceText = PDFDocumentAgentIndex.evidenceText(evidence, locationName: evidenceLocationName())
        guard let coverageText = embeddingCoveragePromptText() else {
            return evidenceText
        }
        return evidenceText.isEmpty ? coverageText : "\(coverageText)\n\n\(evidenceText)"
    }

    func appendEvidenceBubbles(_ evidence: [PDFDocumentAgentEvidence]) {
        if evidence.isEmpty {
            aiPanel.appendNotice(AppText.localized("未检索到明确文档依据，将主要结合当前问题和阅读上下文回答。", "No strong document evidence was found; the answer will rely mostly on the question and reading context."))
            return
        }
        if let top = evidence.first, top.score < 6 {
            aiPanel.appendNotice(AppText.localized("文档依据较弱，回答会以谨慎判断为主。", "Document evidence is weak; the answer will be cautious."))
        }
        let bubbles = evidence.prefix(ReaderAIContextPolicy.evidenceBubbleCount).map { item in
            let label = currentDocumentKind == .pdf
                ? AppText.localized("第 \(item.pageNumber) 页", "Page \(item.pageNumber)")
                : AppText.localized("片段 \(item.pageNumber)", "Section \(item.pageNumber)")
            return AIChatPanel.LinkedWordBubble(
                id: "document-source:\(item.pageIndex)",
                word: label,
                question: AppText.localized("检索依据 \(label)", "Source \(label)"),
                answer: ReaderAIContextPolicy.prefix(item.text, limit: ReaderAIContextPolicy.evidenceBubbleTextLimit)
            )
        }
        aiPanel.appendReferenceBubbles(bubbles)
    }

    func documentTitleForAI() -> String {
        var title = documentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let removableSuffixes = [
            " - PDF Room",
            "- PDF Room",
            " PDF Room",
            "-Chinese-translated",
            "-translated",
            "_Chinese-translated"
        ]
        for suffix in removableSuffixes where title.localizedCaseInsensitiveContains(suffix) {
            title = title.replacingOccurrences(of: suffix, with: "", options: [.caseInsensitive])
        }
        title = title
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -_").union(.whitespacesAndNewlines))
        return title.isEmpty ? documentTitle : title
    }

    func shouldPersistHighlight(for text: String) -> Bool {
        VocabularyTextPolicy.isVocabularySelection(text)
    }
}
