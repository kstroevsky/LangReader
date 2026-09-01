import Foundation
import LeafReaderCore
import PDFKit

/// Deterministic, opt-in interaction driving for performance captures. It is
/// unreachable in normal launches and operates only on disposable fixture
/// copies supplied by the capture script.
extension ReaderWindowController {
    func schedulePerformanceAutomationIfNeeded(for kind: ReaderDocumentKind) {
        scheduleVocabularyPreparationPerformanceAutomationIfNeeded()
        guard ProcessInfo.processInfo.environment["LEAFVOCAB_PERF_AUTOMATION"] == "1",
              kind != .docx,
              performanceAutomationKinds.insert(kind).inserted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.currentDocumentKind == kind else { return }
            switch kind {
            case .pdf:
                self.runPDFPerformanceAutomation()
            case .epub:
                self.runWebPerformanceAutomation()
            case .docx:
                break
            }
        }
    }

    private func scheduleVocabularyPreparationPerformanceAutomationIfNeeded() {
        guard ProcessInfo.processInfo.environment["LEAFVOCAB_PREPARATION_AUTOMATION"] == "1",
              let documentID = currentFileMD5,
              performanceVocabularyPreparationDocumentIDs.insert(documentID).inserted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.currentFileMD5 == documentID else { return }
            self.vocabularyPreparationCoordinator.resetForCurrentDocument()
            self.vocabularyPreparationCoordinator.startAnalysis()
            self.driveVocabularyPreparationAutomation(documentID: documentID, answerIndex: 0)
        }
    }

    private func driveVocabularyPreparationAutomation(documentID: String, answerIndex: Int) {
        guard currentFileMD5 == documentID else { return }
        let coordinator = vocabularyPreparationCoordinator!
        var nextAnswerIndex = answerIndex
        switch coordinator.phase {
        case .inventory:
            coordinator.beginAssessment()
        case .assessment:
            switch coordinator.definitionState {
            case .hidden:
                coordinator.revealCurrentQuestion()
            case .available:
                coordinator.score(answerIndex.isMultiple(of: 3) ? .unknown : .known)
                nextAnswerIndex += 1
            case .loading, .unavailable:
                break
            }
        case .results:
            if coordinator.selectedKeys.isEmpty,
               let first = coordinator.results?.items.first(where: { !coordinator.alreadySavedKeys.contains($0.id) }) {
                coordinator.updateSelection(first.id, selected: true)
            }
            coordinator.createAndReview()
            return
        case .error:
            return
        case .predictionAudit, .predictionAuditResults:
            return
        case .welcome, .analyzing, .importing:
            break
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.driveVocabularyPreparationAutomation(
                documentID: documentID,
                answerIndex: nextAnswerIndex
            )
        }
    }

    private func runPDFPerformanceAutomation() {
        removeStalePerformanceVocabularyRecords()
        performanceAutomationOriginalPDFRecordIDs = Set(storedWordRecords.map(\.id))

        performSearch("Vokabel")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) { [weak self] in
            self?.performSearch("Sprache")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, self.currentDocumentKind == .pdf else { return }
            for _ in 0..<8 { self.goToNextSearchResult() }
            // The paging baseline must not overlap the intentionally common
            // PDFKit search, which can continue streaming results for seconds.
            // Cancellation is itself one of the measured interaction paths.
            self.clearSearchState()
            self.zoomIn()
            self.zoomOut()
            self.measureAutomatedPDFPaging(
                event: .idleScrollFrame,
                frameCount: 24,
                completion: { [weak self] in self?.beginAutomatedVocabularyIndexScenario() }
            )
        }
    }

    private func beginAutomatedVocabularyIndexScenario() {
        let suppressionDelay = suppressSearchSelectionForAIUntil.timeIntervalSinceNow
        if suppressionDelay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + suppressionDelay + 0.05) { [weak self] in
                self?.beginAutomatedVocabularyIndexScenario()
            }
            return
        }
        guard selectPerformanceWord("Vokabel") else { return }
        // PDFKit posts selection-state changes asynchronously. Let the reader
        // observe the programmatic selection before invoking the real Save
        // action, then let language detection and the durable selected record
        // acknowledge before paging can change the current selection.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.currentDocumentKind == .pdf else { return }
            self.saveCurrentPDFVocabularySelection()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.measureAutomatedPDFPaging(event: .backgroundIndexScrollFrame, frameCount: 48)
            }
            self.waitForAutomatedVocabularyIndex(deadline: .now() + 55)
        }
    }

    private func waitForAutomatedVocabularyIndex(deadline: DispatchTime) {
        guard currentDocumentKind == .pdf else { return }
        if documentTextState.vocabularyIndex != nil {
            waitForAutomatedVocabularyPersistence(deadline: .now() + 10)
            return
        }
        guard DispatchTime.now() < deadline else {
            cancelAutomatedVocabularyPersistence()
            cleanupAutomatedVocabularyRecords()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.waitForAutomatedVocabularyIndex(deadline: deadline)
        }
    }

    private func waitForAutomatedVocabularyPersistence(deadline: DispatchTime) {
        guard currentDocumentKind == .pdf else { return }
        if vocabularyState.occurrenceSearchID == nil {
            cleanupAutomatedVocabularyRecords()
            return
        }
        guard DispatchTime.now() < deadline else {
            cancelAutomatedVocabularyPersistence()
            cleanupAutomatedVocabularyRecords()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.waitForAutomatedVocabularyPersistence(deadline: deadline)
        }
    }

    private func cancelAutomatedVocabularyPersistence() {
        vocabularyState.occurrenceSearchCancellationToken?.cancel()
        vocabularyState.occurrenceSearchID = nil
        vocabularyState.occurrenceSearchCancellationToken = nil
    }

    private func removeStalePerformanceVocabularyRecords() {
        guard let store = pdfWordRecordStore else { return }
        let performanceKeys = Set(["Vokabel", "Sprache"].map {
            VocabularyTextPolicy.canonicalVocabularyKey($0)
        })
        let staleIDs = storedWordRecords.compactMap { record in
            performanceKeys.contains(VocabularyTextPolicy.canonicalVocabularyKey(record.word))
                ? record.id
                : nil
        }
        guard !staleIDs.isEmpty, store.delete(ids: staleIDs) else { return }
        let staleIDSet = Set(staleIDs)
        storedWordRecords.removeAll { staleIDSet.contains($0.id) }
    }

    private func selectPerformanceWord(_ word: String) -> Bool {
        guard let document = pdfView.document else { return false }
        for pageIndex in 0..<min(document.pageCount, 8) {
            guard let page = document.page(at: pageIndex), let text = page.string else { continue }
            let range = (text as NSString).range(of: word)
            guard range.location != NSNotFound, let selection = page.selection(for: range) else { continue }
            pdfView.setCurrentSelection(selection, animate: false)
            selectionChanged()
            return true
        }
        return false
    }

    private func measureAutomatedPDFPaging(
        event: PerformanceEvent,
        frameCount: Int,
        completion: (() -> Void)? = nil
    ) {
        guard frameCount > 0,
              pdfView.document?.pageCount ?? 0 > 0,
              let documentView = pdfView.documentView,
              let scrollView = documentView.enclosingScrollView else {
            completion?()
            return
        }
        let clipView = scrollView.contentView
        let startingOrigin = clipView.bounds.origin
        let maximumY = max(0, documentView.bounds.height - clipView.bounds.height)
        let interval: TimeInterval = 1.0 / 30.0
        let start = ProcessInfo.processInfo.systemUptime
        func schedule(_ frame: Int) {
            guard frame < frameCount else {
                completion?()
                return
            }
            let deadline = start + (Double(frame + 1) * interval)
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline - ProcessInfo.processInfo.systemUptime)) { [weak self] in
                guard let self, self.currentDocumentKind == .pdf else { return }
                ReaderPerformance.record(
                    event,
                    milliseconds: max(0, ProcessInfo.processInfo.systemUptime - deadline) * 1_000
                )
                let workStartedAt = ProcessInfo.processInfo.systemUptime
                self.markReaderInteraction()
                // Drive the same clip view that receives ordinary trackpad
                // scrolling. Page navigation triggers a much larger PDFKit
                // relayout/tile lifecycle and is a different interaction.
                let step = CGFloat(frame % 24) * 32
                let direction: CGFloat = (frame / 24).isMultiple(of: 2) ? 1 : -1
                let targetY = min(maximumY, max(0, startingOrigin.y + direction * step))
                clipView.scroll(to: CGPoint(x: startingOrigin.x, y: targetY))
                scrollView.reflectScrolledClipView(clipView)
                ReaderPerformance.recordMainThreadWork(startedAt: workStartedAt)
                schedule(frame + 1)
            }
        }
        schedule(0)
    }

    private func cleanupAutomatedVocabularyRecords() {
        guard let store = pdfWordRecordStore else { return }
        let createdIDs = storedWordRecords
            .map(\.id)
            .filter { !performanceAutomationOriginalPDFRecordIDs.contains($0) }
        guard !createdIDs.isEmpty, store.delete(ids: createdIDs) else { return }
        storedWordRecords.removeAll { createdIDs.contains($0.id) }
    }

    private func runWebPerformanceAutomation() {
        performSearch("Vokabel")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) { [weak self] in
            self?.performSearch("Sprache")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, self.currentDocumentKind == .epub else { return }
            for _ in 0..<8 { self.goToNextSearchResult() }
            self.zoomIn()
            self.zoomOut()
            self.webView.evaluateJavaScript("window.scrollBy(0, Math.max(600, window.innerHeight * 0.8));")
        }
    }
}
