import Cocoa
import NaturalLanguage
import LeafReaderCore

extension ReaderWindowController {
    @objc func showVocabularyPreparation() {
        guard currentFileMD5 != nil else {
            NSSound.beep()
            return
        }
        vocabularyPreparationCoordinator.resetForCurrentDocument()
        vocabularyPreparationPanelController.present()
    }

    func offerVocabularyPreparationIfNeeded(generation: Int) {
        guard ProcessInfo.processInfo.environment["LEAFVOCAB_PERF"] != "1" else { return }
        guard documentSession.acceptsLoad(generation: generation),
              let documentID = currentFileMD5,
              window?.attachedSheet == nil else { return }
        let store = VocabularyPreparationSessionStore(documentID: documentID)
        var session = store.load() ?? VocabularyPreparationSession()
        guard session.invitationState == .notOffered else { return }
        session.invitationState = .offered
        store.save(session)

        let alert = NSAlert()
        alert.messageText = AppText.localized("阅读前准备词汇？", "Prepare vocabulary before reading?")
        alert.informativeText = AppText.localized(
            "可先做 20–80 个快速自评题，再创建一份带概率估计的学习列表。阅读不会被阻止。",
            "Take a quick 20–80 item self-assessment and create a probabilistic learning list. Reading remains available."
        )
        alert.addButton(withTitle: AppText.localized("准备词汇", "Prepare Vocabulary"))
        alert.addButton(withTitle: AppText.localized("暂不", "Not now"))
        alert.applyLeafStyle()
        guard let window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self,
                  self.documentSession.acceptsLoad(generation: generation),
                  self.currentFileMD5 == documentID else { return }
            if response == .alertFirstButtonReturn {
                self.vocabularyPreparationCoordinator.resetForCurrentDocument()
                self.vocabularyPreparationPanelController.present()
                self.vocabularyPreparationCoordinator.startAnalysis()
            } else {
                var dismissed = store.load() ?? session
                dismissed.invitationState = .dismissed
                store.save(dismissed)
            }
        }
    }
}

extension ReaderWindowController: VocabularyPreparationDocumentSource {
    var vocabularyPreparationIdentity: VocabularyPreparationDocumentIdentity? {
        guard let documentID = currentFileMD5 else { return nil }
        return VocabularyPreparationDocumentIdentity(
            documentID: documentID,
            loadGeneration: documentLoadGeneration,
            webPlainTextGeneration: currentDocumentKind == .pdf ? nil : webPlainTextGeneration
        )
    }

    func acceptsVocabularyPreparationIdentity(_ identity: VocabularyPreparationDocumentIdentity) -> Bool {
        vocabularyPreparationIdentity == identity
    }

    func vocabularyPreparationSnapshot(
        requestedLanguage: NLLanguage?
    ) async throws -> VocabularyPreparationSourceSnapshot {
        guard let identity = vocabularyPreparationIdentity else {
            throw VocabularyPreparationSourceError.noDocument
        }
        if currentDocumentKind == .pdf {
            let language = requestedLanguage ?? vocabularyDocumentLanguage
            guard language == .english || language == .german else {
                throw VocabularyPreparationSourceError.unsupportedLanguage
            }
            return try await withCheckedThrowingContinuation { continuation in
                ensurePDFVocabularyIndex(language: language) { [weak self] snapshot, index in
                    guard let self, self.acceptsVocabularyPreparationIdentity(identity) else {
                        continuation.resume(throwing: VocabularyPreparationSourceError.cancelled)
                        return
                    }
                    guard let snapshot, let index else {
                        continuation.resume(throwing: VocabularyPreparationSourceError.textNotReady)
                        return
                    }
                    continuation.resume(returning: VocabularyPreparationSourceSnapshot(
                        identity: identity,
                        kind: .pdf,
                        language: language,
                        texts: snapshot.pageTexts,
                        index: index
                    ))
                }
            }
        }

        let plainText = currentWebPlainText
        guard !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VocabularyPreparationSourceError.textNotReady
        }
        let language = requestedLanguage
            ?? VocabularyLanguageDetector.language(forSample: String(plainText.prefix(8_000)))
        guard language == .english || language == .german else {
            throw VocabularyPreparationSourceError.unsupportedLanguage
        }
        vocabularyDocumentLanguage = language
        guard let index = await Task.detached(priority: .userInitiated, operation: {
            VocabularyDocumentLemmaIndex(
                texts: [plainText],
                language: language,
                maximumWorkerCount: 1,
                isCancelled: { Task.isCancelled }
            )
        }).value else {
            throw VocabularyPreparationSourceError.cancelled
        }
        guard acceptsVocabularyPreparationIdentity(identity) else {
            throw VocabularyPreparationSourceError.cancelled
        }
        return VocabularyPreparationSourceSnapshot(
            identity: identity,
            kind: currentDocumentKind,
            language: language,
            texts: [plainText],
            index: index
        )
    }
}

extension ReaderWindowController: VocabularyPreparationLibraryAccess {
    func vocabularyPreparationExistingKeys(language: NLLanguage, kind: ReaderDocumentKind) -> Set<String> {
        if kind == .pdf {
            return Set(storedWordRecords.map {
                GermanLemmaResolver.groupingKey(word: $0.word, lemma: $0.lemma, language: language)
            })
        }
        return Set(storedWebWordRecords.map {
            GermanLemmaResolver.groupingKey(word: $0.word, lemma: $0.lemma, language: language)
        })
    }

    func persistVocabularyPreparationBatch(
        _ batch: VocabularyPreparationImportBatch,
        documentID: String
    ) async -> Bool {
        await Task.detached(priority: .utility) {
            switch batch {
            case .pdf(let records):
                WordRecordSQLiteStore.shared.upsertPDFRecords(documentID: documentID, records: records)
            case .web(let records):
                WordRecordSQLiteStore.shared.upsertWebRecords(documentID: documentID, records: records)
            }
        }.value
    }

    func finishVocabularyPreparationImport(_ batch: VocabularyPreparationImportBatch) {
        switch batch {
        case .pdf(let records):
            storedWordRecords.append(contentsOf: records)
            addStoredWordAnnotations(records, refineBounds: false)
        case .web(let records):
            storedWebWordRecords.append(contentsOf: records)
            restoreStoredWebWordHighlights()
        }
        refreshVocabularyPanelAfterLocalSave()
        vocabularyPreparationPanelController.close()
        presentVocabularyTrainer()

        for unresolved in batch.unresolvedDefinitions {
            backfillDictionaryAnswerAsync(vocabularyID: unresolved.vocabularyID, word: unresolved.word)
        }
        guard !batch.unresolvedDefinitions.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = AppText.localized(
            "已创建 \(batch.count) 个词汇记录",
            "Created \(batch.count) vocabulary records"
        )
        alert.informativeText = AppText.localized(
            "其中 \(batch.unresolvedDefinitions.count) 个释义仍在后台补充，暂时不可复习。",
            "\(batch.unresolvedDefinitions.count) definitions are still being backfilled and are not reviewable yet."
        )
        alert.addButton(withTitle: AppText.localized("好", "OK"))
        alert.applyLeafStyle()
        if let window { alert.beginSheetModal(for: window) }
    }
}
