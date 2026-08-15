import Cocoa
import NaturalLanguage
import Observation
import LeafReaderCore

enum VocabularyPreparationPhase: Equatable {
    case welcome
    case analyzing
    case inventory
    case assessment
    case results
    case importing
    case error(String)
}

enum VocabularyPreparationDefinitionState: Equatable {
    case hidden
    case loading
    case available(String)
    case unavailable(String)
}

struct VocabularyPreparationInventoryPayload: Sendable {
    let inventory: DocumentVocabularyInventory
    let contexts: [String: String]
    let sourceTexts: [String]
}

private struct VocabularyPreparedDefinition: Sendable {
    let markdown: String
    let tags: String?
    let frequency: Int?
}

private final class VocabularyPreparationCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() { lock.withLock { cancelled = true } }
    var isCancelled: Bool { lock.withLock { cancelled } }
}

private enum VocabularyAssessmentMutation: Sendable {
    case none
    case score(VocabularyAssessmentOutcome, String)
    case exclude(String)
    case skipQuestion
}

private struct VocabularyAssessmentAdvance: Sendable {
    let assessment: AdaptiveVocabularyAssessment
    let candidate: DocumentVocabularyCandidate?
    let result: VocabularyAssessmentResult?
}

@MainActor
@Observable
final class VocabularyPreparationCoordinator {
    private weak var owner: ReaderWindowController?
    private var assessment: AdaptiveVocabularyAssessment?
    private var session = VocabularyPreparationSession()
    private var sessionStore: VocabularyPreparationSessionStore?
    private var requestID = UUID()
    private var cancellationToken = VocabularyPreparationCancellationToken()
    private var sourceTexts: [String] = []
    private var contexts: [String: String] = [:]
    private var definitions: [String: VocabularyPreparedDefinition] = [:]
    private(set) var inventory: DocumentVocabularyInventory?
    private(set) var currentCandidate: DocumentVocabularyCandidate?
    private(set) var definitionState: VocabularyPreparationDefinitionState = .hidden
    private(set) var results: VocabularyAssessmentResult?
    private(set) var alreadySavedKeys = Set<String>()
    var selectedKeys = Set<String>()
    var mode: VocabularyAssessmentMode = .allUnknown
    /// "auto", "en", or "de". The explicit choices support mixed-language
    /// documents without pretending automatic dominant-language detection can
    /// reliably separate both vocabularies.
    var selectedLanguageCode = "auto"
    var phase: VocabularyPreparationPhase = .welcome
    var progressText = ""

    init(owner: ReaderWindowController) {
        self.owner = owner
    }

    var currentContext: String {
        currentCandidate.flatMap { contexts[$0.canonicalKey] } ?? ""
    }

    var answeredCount: Int { assessment?.answeredQuestionCount ?? 0 }
    var hasSavedAnswers: Bool { !session.answers.isEmpty }

    var questionLimitText: String {
        "\(answeredCount) / 80"
    }

    var canScoreCurrentQuestion: Bool {
        if case .available = definitionState { return true }
        return false
    }

    func resetForCurrentDocument() {
        cancel()
        inventory = nil
        currentCandidate = nil
        definitionState = .hidden
        results = nil
        selectedKeys = []
        contexts = [:]
        definitions = [:]
        sourceTexts = []
        phase = .welcome
        progressText = ""
        guard let documentID = owner?.currentFileMD5 else {
            sessionStore = nil
            session = VocabularyPreparationSession()
            return
        }
        let store = VocabularyPreparationSessionStore(documentID: documentID)
        sessionStore = store
        session = store.load() ?? VocabularyPreparationSession()
        mode = session.mode
    }

    func startAnalysis() {
        guard let owner, let documentID = owner.currentFileMD5 else {
            phase = .error(AppText.localized("没有打开的文档。", "No document is open."))
            return
        }
        requestID = UUID()
        cancellationToken.cancel()
        cancellationToken = VocabularyPreparationCancellationToken()
        let activeRequestID = requestID
        let activeToken = cancellationToken
        let loadGeneration = owner.documentLoadGeneration
        session.mode = mode
        session.invitationState = .started
        sessionStore?.save(session)
        phase = .analyzing
        progressText = AppText.localized("正在建立词汇清单…", "Building the vocabulary inventory…")

        if owner.currentDocumentKind == .pdf {
            let language = requestedLanguage ?? owner.vocabularyDocumentLanguage
            guard language == .english || language == .german else {
                phase = .error(AppText.localized(
                    "此版本只支持英语和德语文档。",
                    "This version supports English and German documents only."
                ))
                return
            }
            owner.ensurePDFVocabularyIndex(language: language) { [weak self, weak owner] snapshot, index in
                guard let self, let owner, let snapshot, let index,
                      owner.currentFileMD5 == documentID,
                      owner.documentLoadGeneration == loadGeneration,
                      self.requestID == activeRequestID else { return }
                self.buildPayload(
                    index: index,
                    texts: snapshot.pageTexts,
                    language: language,
                    documentID: documentID,
                    loadGeneration: loadGeneration,
                    webGeneration: nil,
                    requestID: activeRequestID,
                    cancellationToken: activeToken
                )
            }
            return
        }

        let plainText = owner.currentWebPlainText
        guard !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .error(AppText.localized(
                "文档文本仍在载入。请稍后重试。",
                "Document text is still loading. Please retry shortly."
            ))
            return
        }
        let language = requestedLanguage
            ?? VocabularyLanguageDetector.language(forSample: String(plainText.prefix(8_000)))
        guard language == .english || language == .german else {
            phase = .error(AppText.localized(
                "未能检测为英语或德语文档。",
                "The document was not detected as English or German."
            ))
            return
        }
        owner.vocabularyDocumentLanguage = language
        let webGeneration = owner.webPlainTextGeneration
        DispatchQueue.global(qos: .userInitiated).async {
            guard let index = VocabularyDocumentLemmaIndex(
                texts: [plainText],
                language: language,
                maximumWorkerCount: 1,
                isCancelled: { activeToken.isCancelled }
            ) else { return }
            Task { @MainActor [weak self] in
                self?.buildPayload(
                    index: index,
                    texts: [plainText],
                    language: language,
                    documentID: documentID,
                    loadGeneration: loadGeneration,
                    webGeneration: webGeneration,
                    requestID: activeRequestID,
                    cancellationToken: activeToken
                )
            }
        }
    }

    func beginAssessment() {
        guard let inventory else { return }
        var restored = session.answers
        if session.algorithmVersion > VocabularyPreparationSession.currentAlgorithmVersion {
            restored = []
        }
        phase = .analyzing
        progressText = AppText.localized("正在选择第一道题…", "Selecting the first question…")
        let activeRequestID = requestID
        let mode = mode
        Task.detached { [weak self] in
            let assessment = AdaptiveVocabularyAssessment(
                inventory: inventory,
                mode: mode,
                restoredAnswers: restored
            )
            let advance = Self.advance(assessment, mutation: .none)
            await self?.apply(advance: advance, requestID: activeRequestID, persistAnswers: false)
        }
    }

    func resetAssessment() {
        assessment = nil
        currentCandidate = nil
        definitionState = .hidden
        results = nil
        selectedKeys = []
        definitions = [:]
        session.answers = []
        session.finalSelection = []
        session.algorithmVersion = VocabularyPreparationSession.currentAlgorithmVersion
        sessionStore?.save(session)
        phase = inventory == nil ? .welcome : .inventory
    }

    func revealCurrentQuestion() {
        guard let candidate = currentCandidate else { return }
        if let cached = definitionFromResults(for: candidate.canonicalKey) {
            definitionState = .available(cached)
            return
        }
        definitionState = .loading
        let languageCode = inventory?.languageCode
        let context = contexts[candidate.canonicalKey] ?? ""
        let activeRequestID = requestID
        if languageCode == NLLanguage.german.rawValue {
            Task { [weak self] in
                do {
                    let entry = try await GermanWiktionaryDictionary.shared.lookup(candidate.displayLemma)
                    guard !Task.isCancelled, let self, self.requestID == activeRequestID else { return }
                    self.definitions[candidate.canonicalKey] = VocabularyPreparedDefinition(
                        markdown: entry.markdown,
                        tags: entry.metadata.tags,
                        frequency: candidate.generalFrequencyRank
                    )
                    self.definitionState = .available(entry.markdown)
                } catch {
                    guard let self, self.requestID == activeRequestID else { return }
                    self.definitionState = .unavailable(error.localizedDescription)
                }
            }
        } else {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let answer = LocalDictionaryLookupService.shared.dictionaryAnswer(
                    for: candidate.displayLemma,
                    context: context
                )?.markdown
                Task { @MainActor [weak self] in
                    guard let self, self.requestID == activeRequestID else { return }
                    if let answer {
                        let metadata = LocalDictionaryLookupService.shared.metadata(for: candidate.displayLemma)
                        self.definitions[candidate.canonicalKey] = VocabularyPreparedDefinition(
                            markdown: answer,
                            tags: metadata.tags,
                            frequency: candidate.generalFrequencyRank ?? metadata.frequency
                        )
                    }
                    self.definitionState = answer.map(VocabularyPreparationDefinitionState.available)
                        ?? .available(AppText.localized("本地词典中没有释义。", "No local definition is available."))
                }
            }
        }
    }

    func retryDefinition() {
        definitionState = .hidden
        revealCurrentQuestion()
    }

    func skipDefinition() {
        advanceAssessment(.skipQuestion, persistAnswers: false)
    }

    func score(_ outcome: VocabularyAssessmentOutcome) {
        guard outcome != .excluded, canScoreCurrentQuestion, let key = currentCandidate?.canonicalKey else { return }
        advanceAssessment(.score(outcome, key), persistAnswers: true)
    }

    func excludeCurrentCandidate() {
        guard let key = currentCandidate?.canonicalKey else { return }
        advanceAssessment(.exclude(key), persistAnswers: true)
    }

    func updateSelection(_ key: String, selected: Bool) {
        guard !alreadySavedKeys.contains(key) else { return }
        if selected { selectedKeys.insert(key) } else { selectedKeys.remove(key) }
        session.finalSelection = selectedKeys
        sessionStore?.save(session)
        if let results {
            self.results = results.applyingSelection(selectedKeys)
        }
    }

    func createAndReview() {
        guard let owner, let inventory, !selectedKeys.isEmpty,
              let documentID = owner.currentFileMD5 else { return }
        let selected = inventory.candidates.filter {
            selectedKeys.contains($0.canonicalKey) && !alreadySavedKeys.contains($0.canonicalKey)
        }
        guard !selected.isEmpty else { return }

        let activeRequestID = requestID
        let loadGeneration = owner.documentLoadGeneration
        let languageCode = inventory.languageCode
        phase = .importing
        progressText = AppText.localized("正在准备释义…", "Preparing definitions…")

        if languageCode == NLLanguage.german.rawValue {
            Task { [weak self] in
                guard let self else { return }
                var resolved = self.definitions
                let missing = selected.filter { resolved[$0.canonicalKey] == nil }
                var iterator = missing.makeIterator()
                await withTaskGroup(of: (String, VocabularyPreparedDefinition?).self) { group in
                    func addNext() {
                        guard let candidate = iterator.next() else { return }
                        group.addTask {
                            let entry = try? await GermanWiktionaryDictionary.shared.lookup(candidate.displayLemma)
                            return (
                                candidate.canonicalKey,
                                entry.map {
                                    VocabularyPreparedDefinition(
                                        markdown: $0.markdown,
                                        tags: $0.metadata.tags,
                                        frequency: candidate.generalFrequencyRank
                                    )
                                }
                            )
                        }
                    }
                    for _ in 0..<min(4, missing.count) { addNext() }
                    while let (key, definition) = await group.next() {
                        if let definition { resolved[key] = definition }
                        addNext()
                    }
                }
                guard !Task.isCancelled, self.requestID == activeRequestID else { return }
                self.finishImport(
                    selected: selected,
                    definitions: resolved,
                    documentID: documentID,
                    loadGeneration: loadGeneration,
                    requestID: activeRequestID
                )
            }
            return
        }

        let cachedDefinitions = definitions
        let candidateContexts = contexts
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var resolved = cachedDefinitions
            for candidate in selected where resolved[candidate.canonicalKey] == nil {
                let context = candidateContexts[candidate.canonicalKey] ?? ""
                let lookup = LocalDictionaryLookupService.shared.dictionaryAnswer(
                    for: candidate.displayLemma,
                    context: context
                )
                resolved[candidate.canonicalKey] = VocabularyPreparedDefinition(
                    markdown: lookup?.markdown ?? "",
                    tags: lookup?.metadata.tags,
                    frequency: candidate.generalFrequencyRank ?? lookup?.metadata.frequency
                )
            }
            Task { @MainActor [weak self] in
                self?.finishImport(
                    selected: selected,
                    definitions: resolved,
                    documentID: documentID,
                    loadGeneration: loadGeneration,
                    requestID: activeRequestID
                )
            }
        }
    }

    func cancel() {
        requestID = UUID()
        cancellationToken.cancel()
    }

    private func buildPayload(
        index: VocabularyDocumentLemmaIndex,
        texts: [String],
        language: NLLanguage,
        documentID: String,
        loadGeneration: Int,
        webGeneration: Int?,
        requestID: UUID,
        cancellationToken: VocabularyPreparationCancellationToken
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard !cancellationToken.isCancelled else { return }
            let summaries = index.lemmaSummaries()
            let difficultyProvider = language == .german
                ? DocumentVocabularyFrequencyProvider.german
                : DocumentVocabularyFrequencyProvider.english
            let inventory = DocumentVocabularyInventory(
                summaries: summaries,
                languageCode: language.rawValue,
                maximumFrequencyRank: difficultyProvider.frequencyScale.maximumRank
            ) { summary in
                difficultyProvider.bestRank(for: summary)
            }
            guard !cancellationToken.isCancelled else { return }
            let contexts = Dictionary(uniqueKeysWithValues: inventory.candidates.map { candidate in
                (candidate.canonicalKey, Self.context(for: candidate.representativeRange, texts: texts))
            })
            let payload = VocabularyPreparationInventoryPayload(
                inventory: inventory,
                contexts: contexts,
                sourceTexts: texts
            )
            Task { @MainActor [weak self] in
                guard let self, let owner = self.owner,
                      self.requestID == requestID,
                      owner.currentFileMD5 == documentID,
                      owner.documentLoadGeneration == loadGeneration,
                      webGeneration == nil || owner.webPlainTextGeneration == webGeneration else { return }
                self.apply(payload: payload)
            }
        }
    }

    private func apply(payload: VocabularyPreparationInventoryPayload) {
        inventory = payload.inventory
        contexts = payload.contexts
        sourceTexts = payload.sourceTexts
        alreadySavedKeys = existingVocabularyKeys()
        phase = .inventory
        progressText = AppText.localized(
            "找到 \(payload.inventory.candidates.count) 个可测试词元。",
            "Found \(payload.inventory.candidates.count) assessable lemmas."
        )
    }

    private func advanceAssessment(_ mutation: VocabularyAssessmentMutation, persistAnswers: Bool) {
        guard let assessment else { return }
        phase = .analyzing
        progressText = AppText.localized("正在更新估计…", "Updating the estimate…")
        currentCandidate = nil
        definitionState = .hidden
        let activeRequestID = requestID
        Task.detached { [weak self] in
            let advance = Self.advance(assessment, mutation: mutation)
            await self?.apply(
                advance: advance,
                requestID: activeRequestID,
                persistAnswers: persistAnswers
            )
        }
    }

    nonisolated private static func advance(
        _ assessment: AdaptiveVocabularyAssessment,
        mutation: VocabularyAssessmentMutation
    ) -> VocabularyAssessmentAdvance {
        var assessment = assessment
        switch mutation {
        case .none:
            break
        case let .score(outcome, key):
            assessment.record(outcome, for: key)
        case let .exclude(key):
            assessment.record(.excluded, for: key)
        case .skipQuestion:
            assessment.skipCurrentQuestion()
        }
        if assessment.isFinished {
            return VocabularyAssessmentAdvance(
                assessment: assessment,
                candidate: nil,
                result: assessment.result()
            )
        }
        let candidate = assessment.nextQuestion()
        return VocabularyAssessmentAdvance(
            assessment: assessment,
            candidate: candidate,
            result: candidate == nil ? assessment.result() : nil
        )
    }

    private func apply(
        advance: VocabularyAssessmentAdvance,
        requestID: UUID,
        persistAnswers: Bool
    ) {
        guard self.requestID == requestID else { return }
        assessment = advance.assessment
        if persistAnswers { persistAssessment() }
        if let result = advance.result {
            showResults(result)
            return
        }
        currentCandidate = advance.candidate
        definitionState = .hidden
        phase = .assessment
    }

    private func showResults(_ proposed: VocabularyAssessmentResult) {
        let restored = session.finalSelection
        let baseSelection = restored.isEmpty
            ? Set(proposed.items.filter(\.isSelected).map(\.id))
            : restored
        selectedKeys = baseSelection.subtracting(alreadySavedKeys)
        results = proposed.applyingSelection(selectedKeys)
        session.finalSelection = selectedKeys
        sessionStore?.save(session)
        phase = .results
    }

    private func persistAssessment() {
        guard let assessment else { return }
        session.mode = mode
        session.answers = assessment.answers
        session.algorithmVersion = VocabularyPreparationSession.currentAlgorithmVersion
        sessionStore?.save(session)
    }

    private func existingVocabularyKeys() -> Set<String> {
        guard let owner else { return [] }
        let language = owner.vocabularyDocumentLanguage
        if owner.currentDocumentKind == .pdf {
            return Set(owner.storedWordRecords.map {
                GermanLemmaResolver.groupingKey(word: $0.word, lemma: $0.lemma, language: language)
            })
        }
        return Set(owner.storedWebWordRecords.map {
            GermanLemmaResolver.groupingKey(word: $0.word, lemma: $0.lemma, language: language)
        })
    }

    private func definitionFromResults(for key: String) -> String? {
        definitions[key]?.markdown
    }

    private var requestedLanguage: NLLanguage? {
        switch selectedLanguageCode {
        case "en": .english
        case "de": .german
        default: nil
        }
    }

    private func finishImport(
        selected: [DocumentVocabularyCandidate],
        definitions: [String: VocabularyPreparedDefinition],
        documentID: String,
        loadGeneration: Int,
        requestID: UUID
    ) {
        guard let owner,
              self.requestID == requestID,
              owner.currentFileMD5 == documentID,
              owner.documentLoadGeneration == loadGeneration else { return }
        self.definitions = definitions
        let createdAt = Date()
        let existingKeys = existingVocabularyKeys()
        let candidates = selected.filter { !existingKeys.contains($0.canonicalKey) }
        let kind = owner.currentDocumentKind
        let texts = sourceTexts

        let pdfRecords: [StoredPDFWordRecord]
        let webRecords: [StoredWebWordRecord]
        if kind == .pdf {
            pdfRecords = candidates.compactMap { candidate in
                let range = candidate.representativeRange
                guard texts.indices.contains(range.unitIndex),
                      let anchor = TextQuoteAnchor(
                        unitOrdinal: range.unitIndex,
                        sourceRange: NSRange(location: range.utf16Location, length: range.utf16Length),
                        sourceText: texts[range.unitIndex]
                      ) else { return nil }
                let definition = definitions[candidate.canonicalKey]
                return StoredPDFWordRecord(
                    id: UUID().uuidString,
                    vocabularyID: UUID().uuidString,
                    word: candidate.displayLemma,
                    lemma: candidate.displayLemma,
                    surfaceForm: candidate.observedForms.first?.surface ?? candidate.displayLemma,
                    pageIndex: range.unitIndex,
                    bounds: StoredPDFWordRect(.zero),
                    textAnchor: anchor,
                    context: contexts[candidate.canonicalKey] ?? "",
                    question: "",
                    answer: definition?.markdown ?? "",
                    dictionaryTags: definition?.tags,
                    dictionaryFrequency: candidate.generalFrequencyRank ?? definition?.frequency,
                    createdAt: createdAt,
                    srs: VocabularySRSState.initial(createdAt: createdAt)
                )
            }
            webRecords = []
        } else {
            pdfRecords = []
            let textLength = max(1, texts.first?.utf16.count ?? 0)
            webRecords = candidates.map { candidate in
                let definition = definitions[candidate.canonicalKey]
                let range = candidate.representativeRange
                return StoredWebWordRecord(
                    id: UUID().uuidString,
                    vocabularyID: UUID().uuidString,
                    word: candidate.displayLemma,
                    lemma: candidate.displayLemma,
                    surfaceForm: candidate.observedForms.first?.surface ?? candidate.displayLemma,
                    context: contexts[candidate.canonicalKey] ?? "",
                    occurrenceIndex: nil,
                    scrollProgress: min(1, max(0, Double(range.utf16Location) / Double(textLength))),
                    question: "",
                    answer: definition?.markdown ?? "",
                    dictionaryTags: definition?.tags,
                    dictionaryFrequency: candidate.generalFrequencyRank ?? definition?.frequency,
                    createdAt: createdAt,
                    srs: VocabularySRSState.initial(createdAt: createdAt)
                )
            }
        }
        progressText = AppText.localized("正在原子写入词库…", "Saving the vocabulary set atomically…")
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let didPersist = kind == .pdf
                ? WordRecordSQLiteStore.shared.upsertPDFRecords(documentID: documentID, records: pdfRecords)
                : WordRecordSQLiteStore.shared.upsertWebRecords(documentID: documentID, records: webRecords)
            Task { @MainActor [weak self] in
                guard let self, let owner = self.owner,
                      self.requestID == requestID,
                      owner.currentFileMD5 == documentID,
                      owner.documentLoadGeneration == loadGeneration else { return }
                guard didPersist else {
                    self.phase = .error(AppText.localized(
                        "无法写入词库；没有创建任何记录。",
                        "The vocabulary library could not be updated; no records were created."
                    ))
                    return
                }
                if kind == .pdf {
                    owner.storedWordRecords.append(contentsOf: pdfRecords)
                    owner.addStoredWordAnnotations(pdfRecords, refineBounds: false)
                } else {
                    owner.storedWebWordRecords.append(contentsOf: webRecords)
                    owner.restoreStoredWebWordHighlights()
                }
                self.session.invitationState = .completed
                self.session.finalSelection = self.selectedKeys
                self.sessionStore?.save(self.session)
                owner.refreshVocabularyPanelAfterLocalSave()
                owner.vocabularyPreparationPanelController.close()
                owner.presentVocabularyTrainer()

                let unresolved = (kind == .pdf ? pdfRecords.map { ($0.vocabularyID, $0.word, $0.answer) } : webRecords.map { ($0.vocabularyID, $0.word, $0.answer) })
                    .filter { $0.2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                for record in unresolved {
                    owner.backfillDictionaryAnswerAsync(vocabularyID: record.0, word: record.1)
                }
                if !unresolved.isEmpty {
                    let alert = NSAlert()
                    alert.messageText = AppText.localized(
                        "已创建 \(pdfRecords.count + webRecords.count) 个词汇记录",
                        "Created \(pdfRecords.count + webRecords.count) vocabulary records"
                    )
                    alert.informativeText = AppText.localized(
                        "其中 \(unresolved.count) 个释义仍在后台补充，暂时不可复习。",
                        "\(unresolved.count) definitions are still being backfilled and are not reviewable yet."
                    )
                    alert.addButton(withTitle: AppText.localized("好", "OK"))
                    alert.applyLeafStyle()
                    if let window = owner.window { alert.beginSheetModal(for: window) }
                }
            }
        }
    }

    nonisolated private static func context(
        for sourceRange: VocabularyDocumentSourceRange,
        texts: [String]
    ) -> String {
        guard texts.indices.contains(sourceRange.unitIndex) else { return "" }
        let source = texts[sourceRange.unitIndex] as NSString
        let start = max(0, sourceRange.utf16Location - 100)
        let end = min(source.length, sourceRange.utf16Location + sourceRange.utf16Length + 100)
        guard end > start else { return "" }
        return source.substring(with: NSRange(location: start, length: end - start))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
