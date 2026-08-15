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
    let durationMilliseconds: Double
}

@MainActor
@Observable
final class VocabularyPreparationCoordinator {
    private weak var documentSource: (any VocabularyPreparationDocumentSource)?
    private weak var library: (any VocabularyPreparationLibraryAccess)?
    private let definitionProvider: any VocabularyPreparationDefinitionProviding
    private var assessment: AdaptiveVocabularyAssessment?
    private var session = VocabularyPreparationSession()
    private var sessionStore: VocabularyPreparationSessionStore?
    private var requestID = UUID()
    private var cancellationToken = VocabularyPreparationCancellationToken()
    private var sourceTexts: [String] = []
    private var contexts: [String: String] = [:]
    private var definitions: [String: VocabularyPreparedDefinition] = [:]
    private var definitionFailures: [String: String] = [:]
    private var definitionTask: Task<Void, Never>?
    private var workflowTask: Task<Void, Never>?
    private var revealedDefinitionKey: String?
    private var activeIdentity: VocabularyPreparationDocumentIdentity?
    private var activeDocumentKind: ReaderDocumentKind?
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

    init(
        documentSource: any VocabularyPreparationDocumentSource,
        library: any VocabularyPreparationLibraryAccess,
        definitionProvider: any VocabularyPreparationDefinitionProviding = LiveVocabularyPreparationDefinitionProvider()
    ) {
        self.documentSource = documentSource
        self.library = library
        self.definitionProvider = definitionProvider
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
        definitionFailures = [:]
        revealedDefinitionKey = nil
        activeIdentity = nil
        activeDocumentKind = nil
        sourceTexts = []
        phase = .welcome
        progressText = ""
        guard let documentID = documentSource?.vocabularyPreparationIdentity?.documentID else {
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
        guard let documentSource else {
            phase = .error(AppText.localized("没有打开的文档。", "No document is open."))
            return
        }
        requestID = UUID()
        cancellationToken.cancel()
        cancellationToken = VocabularyPreparationCancellationToken()
        workflowTask?.cancel()
        let activeRequestID = requestID
        let activeToken = cancellationToken
        session.mode = mode
        session.invitationState = .started
        sessionStore?.save(session)
        phase = .analyzing
        progressText = AppText.localized("正在建立词汇清单…", "Building the vocabulary inventory…")
        let analysisStartedAt = ProcessInfo.processInfo.systemUptime

        workflowTask = Task { [weak self, weak documentSource] in
            do {
                guard let snapshot = try await documentSource?.vocabularyPreparationSnapshot(
                    requestedLanguage: self?.requestedLanguage
                ), let self,
                self.requestID == activeRequestID,
                !activeToken.isCancelled,
                documentSource?.acceptsVocabularyPreparationIdentity(snapshot.identity) == true else { return }
                self.activeIdentity = snapshot.identity
                self.activeDocumentKind = snapshot.kind
                self.buildPayload(
                    snapshot: snapshot,
                    requestID: activeRequestID,
                    cancellationToken: activeToken,
                    analysisStartedAt: analysisStartedAt
                )
            } catch {
                guard let self, self.requestID == activeRequestID, !activeToken.isCancelled else { return }
                if case VocabularyPreparationSourceError.cancelled = error { return }
                self.phase = .error(error.localizedDescription)
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
        definitionTask?.cancel()
        definitionTask = nil
        assessment = nil
        currentCandidate = nil
        definitionState = .hidden
        results = nil
        selectedKeys = []
        definitions = [:]
        definitionFailures = [:]
        revealedDefinitionKey = nil
        session.answers = []
        session.finalSelection = []
        session.algorithmVersion = VocabularyPreparationSession.currentAlgorithmVersion
        sessionStore?.save(session)
        phase = inventory == nil ? .welcome : .inventory
    }

    func revealCurrentQuestion() {
        guard let candidate = currentCandidate else { return }
        revealedDefinitionKey = candidate.canonicalKey
        if let cached = definitionFromResults(for: candidate.canonicalKey) {
            definitionState = .available(cached)
            return
        }
        if let failure = definitionFailures[candidate.canonicalKey] {
            definitionState = .unavailable(failure)
            return
        }
        definitionState = .loading
        if definitionTask == nil { prefetchDefinition(for: candidate) }
    }

    func retryDefinition() {
        guard let candidate = currentCandidate else { return }
        definitionFailures[candidate.canonicalKey] = nil
        definitionState = .hidden
        definitionTask?.cancel()
        definitionTask = nil
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
        guard let inventory, !selectedKeys.isEmpty,
              let identity = activeIdentity,
              documentSource?.acceptsVocabularyPreparationIdentity(identity) == true,
              library != nil else { return }
        let selected = inventory.candidates.filter {
            selectedKeys.contains($0.canonicalKey) && !alreadySavedKeys.contains($0.canonicalKey)
        }
        guard !selected.isEmpty else { return }

        let activeRequestID = requestID
        let languageCode = inventory.languageCode
        phase = .importing
        progressText = AppText.localized("正在准备释义…", "Preparing definitions…")
        let provider = definitionProvider
        let candidateContexts = contexts
        let importStartedAt = ProcessInfo.processInfo.systemUptime
        workflowTask?.cancel()
        workflowTask = Task { [weak self] in
            guard let self else { return }
            var resolved = self.definitions
            let missing = selected.filter { resolved[$0.canonicalKey] == nil }
            var iterator = missing.makeIterator()
            await withTaskGroup(of: (String, VocabularyPreparedDefinition?).self) { group in
                func addNext() {
                    guard let candidate = iterator.next() else { return }
                    group.addTask {
                        let definition = try? await provider.definition(
                            for: candidate,
                            languageCode: languageCode,
                            context: candidateContexts[candidate.canonicalKey] ?? ""
                        )
                        return (candidate.canonicalKey, definition)
                    }
                }
                for _ in 0..<min(4, missing.count) { addNext() }
                while let (key, definition) = await group.next() {
                    if let definition { resolved[key] = definition }
                    addNext()
                }
            }
            guard !Task.isCancelled,
                  self.requestID == activeRequestID,
                  self.documentSource?.acceptsVocabularyPreparationIdentity(identity) == true else { return }
            await self.finishImport(
                selected: selected,
                definitions: resolved,
                identity: identity,
                requestID: activeRequestID,
                importStartedAt: importStartedAt
            )
        }
    }

    func cancel() {
        requestID = UUID()
        cancellationToken.cancel()
        workflowTask?.cancel()
        workflowTask = nil
        definitionTask?.cancel()
        definitionTask = nil
    }

    private func buildPayload(
        snapshot: VocabularyPreparationSourceSnapshot,
        requestID: UUID,
        cancellationToken: VocabularyPreparationCancellationToken,
        analysisStartedAt: TimeInterval
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard !cancellationToken.isCancelled else { return }
            let summaries = snapshot.index.lemmaSummaries()
            let difficultyProvider = snapshot.language == .german
                ? DocumentVocabularyFrequencyProvider.german
                : DocumentVocabularyFrequencyProvider.english
            let inventory = DocumentVocabularyInventory(
                summaries: summaries,
                languageCode: snapshot.language.rawValue,
                maximumFrequencyRank: difficultyProvider.frequencyScale.maximumRank
            ) { summary in
                difficultyProvider.bestRank(for: summary)
            }
            guard !cancellationToken.isCancelled else { return }
            let contexts = Dictionary(uniqueKeysWithValues: inventory.candidates.map { candidate in
                (candidate.canonicalKey, Self.context(for: candidate.representativeRange, texts: snapshot.texts))
            })
            let payload = VocabularyPreparationInventoryPayload(
                inventory: inventory,
                contexts: contexts,
                sourceTexts: snapshot.texts
            )
            Task { @MainActor [weak self] in
                guard let self,
                      self.requestID == requestID,
                      self.documentSource?.acceptsVocabularyPreparationIdentity(snapshot.identity) == true else { return }
                self.apply(
                    payload: payload,
                    durationMilliseconds: (ProcessInfo.processInfo.systemUptime - analysisStartedAt) * 1_000
                )
            }
        }
    }

    private func apply(payload: VocabularyPreparationInventoryPayload, durationMilliseconds: Double) {
        let mainWorkStartedAt = ProcessInfo.processInfo.systemUptime
        inventory = payload.inventory
        contexts = payload.contexts
        sourceTexts = payload.sourceTexts
        alreadySavedKeys = existingVocabularyKeys()
        phase = .inventory
        progressText = AppText.localized(
            "找到 \(payload.inventory.candidates.count) 个可测试词元。",
            "Found \(payload.inventory.candidates.count) assessable lemmas."
        )
        ReaderPerformance.record(.vocabularyPreparationInventoryBuild, milliseconds: durationMilliseconds)
        ReaderPerformance.recordMainThreadWork(startedAt: mainWorkStartedAt)
    }

    private func advanceAssessment(_ mutation: VocabularyAssessmentMutation, persistAnswers: Bool) {
        guard let assessment else { return }
        definitionTask?.cancel()
        definitionTask = nil
        revealedDefinitionKey = nil
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
        let startedAt = ProcessInfo.processInfo.systemUptime
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
                result: assessment.result(),
                durationMilliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
            )
        }
        let candidate = assessment.nextQuestion()
        return VocabularyAssessmentAdvance(
            assessment: assessment,
            candidate: candidate,
            result: candidate == nil ? assessment.result() : nil,
            durationMilliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        )
    }

    private func apply(
        advance: VocabularyAssessmentAdvance,
        requestID: UUID,
        persistAnswers: Bool
    ) {
        guard self.requestID == requestID,
              let identity = activeIdentity,
              documentSource?.acceptsVocabularyPreparationIdentity(identity) == true else { return }
        ReaderPerformance.record(.vocabularyAssessmentAdvance, milliseconds: advance.durationMilliseconds)
        assessment = advance.assessment
        if persistAnswers { persistAssessment() }
        if let result = advance.result {
            showResults(result)
            return
        }
        currentCandidate = advance.candidate
        definitionState = .hidden
        phase = .assessment
        if let candidate = advance.candidate {
            prefetchDefinition(for: candidate)
        }
    }

    private func prefetchDefinition(for candidate: DocumentVocabularyCandidate) {
        guard definitionTask == nil,
              definitions[candidate.canonicalKey] == nil,
              definitionFailures[candidate.canonicalKey] == nil,
              let languageCode = inventory?.languageCode,
              let identity = activeIdentity else { return }
        let key = candidate.canonicalKey
        let context = contexts[key] ?? ""
        let activeRequestID = requestID
        let provider = definitionProvider
        definitionTask = Task { [weak self] in
            do {
                let definition = try await provider.definition(
                    for: candidate,
                    languageCode: languageCode,
                    context: context
                )
                guard !Task.isCancelled, let self,
                      self.requestID == activeRequestID,
                      self.currentCandidate?.canonicalKey == key,
                      self.documentSource?.acceptsVocabularyPreparationIdentity(identity) == true else { return }
                self.definitions[key] = definition
                self.definitionTask = nil
                if self.revealedDefinitionKey == key {
                    self.definitionState = .available(definition.markdown)
                }
            } catch {
                guard !Task.isCancelled, let self,
                      self.requestID == activeRequestID,
                      self.currentCandidate?.canonicalKey == key,
                      self.documentSource?.acceptsVocabularyPreparationIdentity(identity) == true else { return }
                self.definitionFailures[key] = error.localizedDescription
                self.definitionTask = nil
                if self.revealedDefinitionKey == key {
                    self.definitionState = .unavailable(error.localizedDescription)
                }
            }
        }
    }

    private func showResults(_ proposed: VocabularyAssessmentResult) {
        let mainWorkStartedAt = ProcessInfo.processInfo.systemUptime
        let span = ReaderPerformance.begin(.vocabularyPreparationResults)
        defer {
            ReaderPerformance.end(span)
            ReaderPerformance.recordMainThreadWork(startedAt: mainWorkStartedAt)
        }
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
        guard let library, let kind = activeDocumentKind,
              let languageCode = inventory?.languageCode else { return [] }
        return library.vocabularyPreparationExistingKeys(
            language: NLLanguage(rawValue: languageCode),
            kind: kind
        )
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
        identity: VocabularyPreparationDocumentIdentity,
        requestID: UUID,
        importStartedAt: TimeInterval
    ) async {
        guard let library, let kind = activeDocumentKind,
              self.requestID == requestID,
              documentSource?.acceptsVocabularyPreparationIdentity(identity) == true else { return }
        self.definitions = definitions
        let createdAt = Date()
        let existingKeys = existingVocabularyKeys()
        let candidates = selected.filter { !existingKeys.contains($0.canonicalKey) }
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
        let batch: VocabularyPreparationImportBatch = kind == .pdf ? .pdf(pdfRecords) : .web(webRecords)
        let didPersist = await library.persistVocabularyPreparationBatch(batch, documentID: identity.documentID)
        guard self.requestID == requestID,
              documentSource?.acceptsVocabularyPreparationIdentity(identity) == true else { return }
        ReaderPerformance.record(
            .vocabularyPreparationImport,
            milliseconds: (ProcessInfo.processInfo.systemUptime - importStartedAt) * 1_000
        )
        guard didPersist else {
            phase = .error(AppText.localized(
                "无法写入词库；没有创建任何记录。",
                "The vocabulary library could not be updated; no records were created."
            ))
            return
        }
        session.invitationState = .completed
        session.finalSelection = selectedKeys
        sessionStore?.save(session)
        let mainWorkStartedAt = ProcessInfo.processInfo.systemUptime
        library.finishVocabularyPreparationImport(batch)
        ReaderPerformance.recordMainThreadWork(startedAt: mainWorkStartedAt)
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
