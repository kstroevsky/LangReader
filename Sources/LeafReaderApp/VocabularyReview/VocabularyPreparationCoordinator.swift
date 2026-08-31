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
    case predictionAudit
    case predictionAuditResults
    case importing
    case error(String)
}

enum VocabularyPreparationDefinitionState: Equatable {
    case hidden
    case loading
    case available(String)
    case unavailable(String)
}

enum VocabularyAssessmentInteractionState: Equatable {
    case awaitingAnswer
    case pendingKnownVerification
    case learningAfterAnswer
}

struct VocabularyPreparationInventoryPayload: Sendable {
    let inventory: DocumentVocabularyInventory
    let domainDetection: VocabularyDocumentDomainDetection?
    let contexts: [String: String]
    let sourceTexts: [String]
    let readerPrior: VocabularyReaderPrior?
    let sourceSnapshotMilliseconds: Double
    let inventoryModelMilliseconds: Double
    let contextMaterializationMilliseconds: Double
}

private final class VocabularyPreparationCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() { lock.withLock { cancelled = true } }
    var isCancelled: Bool { lock.withLock { cancelled } }
}

private enum VocabularyAssessmentMutation: Sendable {
    case none
    case score(VocabularyKnowledgeEvidence, String, typedMeaning: String?)
    case exclude(String)
    case skipQuestion
}

private struct VocabularyAssessmentAdvance: Sendable {
    let assessment: AdaptiveVocabularyAssessment
    let candidate: DocumentVocabularyCandidate?
    let result: VocabularyAssessmentResult?
    let durationMilliseconds: Double
    let initializationMilliseconds: Double
    let posteriorUpdateMilliseconds: Double
    let nextQuestionMilliseconds: Double
    let resultBuildMilliseconds: Double
    let holdsAnsweredCandidate: Bool
}

private struct VocabularyPendingKnownScore: Equatable, Sendable {
    let canonicalKey: String
    let evidence: VocabularyKnowledgeEvidence
    let typedMeaning: String?
}

@MainActor
@Observable
final class VocabularyPreparationCoordinator {
    private weak var documentSource: (any VocabularyPreparationDocumentSource)?
    private weak var library: (any VocabularyPreparationLibraryAccess)?
    private let definitionProvider: any VocabularyPreparationDefinitionProviding
    private let readerPriorStore: any VocabularyReaderPriorStoring
    private let researchEvidenceStore: any VocabularyResearchEvidenceStoring
    private var assessment: AdaptiveVocabularyAssessment?
    private var session = VocabularyPreparationSession()
    private var sessionStore: VocabularyPreparationSessionStore?
    private var requestID = UUID()
    private var cancellationToken = VocabularyPreparationCancellationToken()
    private var sourceTexts: [String] = []
    private var readerPrior: VocabularyReaderPrior?
    private var contexts: [String: String] = [:]
    private var definitions: [String: VocabularyPreparedDefinition] = [:]
    private var definitionFailures: [String: String] = [:]
    private var definitionTask: Task<Void, Never>?
    private var workflowTask: Task<Void, Never>?
    private var assessmentUpdatePending = false
    private var continueAfterPendingAssessmentUpdate = false
    private var knownAdvanceTask: Task<Void, Never>?
    private var precomputedKnownAdvance: VocabularyAssessmentAdvance?
    private var precomputedKnownScore: VocabularyPendingKnownScore?
    private var pendingKnownScore: VocabularyPendingKnownScore?
    private var revealedDefinitionKey: String?
    private var activeIdentity: VocabularyPreparationDocumentIdentity?
    private var activeDocumentKind: ReaderDocumentKind?
    private(set) var inventory: DocumentVocabularyInventory?
    private(set) var currentCandidate: DocumentVocabularyCandidate?
    private(set) var definitionState: VocabularyPreparationDefinitionState = .hidden
    private(set) var interactionState: VocabularyAssessmentInteractionState = .awaitingAnswer
    private(set) var results: VocabularyAssessmentResult?
    private(set) var alreadySavedKeys = Set<String>()
    private(set) var domainDetection: VocabularyDocumentDomainDetection?
    private(set) var isPreparingNextQuestion = false
    private(set) var isKnownAnswerPrepared = false
    var selectedKeys = Set<String>()
    var mode: VocabularyAssessmentMode = .allUnknown
    /// "auto", "en", or "de". The explicit choices support mixed-language
    /// documents without pretending automatic dominant-language detection can
    /// reliably separate both vocabularies.
    var selectedLanguageCode = "auto"
    var phase: VocabularyPreparationPhase = .welcome
    var progressText = ""
    var typedModeEnabled = false
    var typedMeaningDraft = ""

    var experimentalDomainsEnabled: Bool {
        UserDefaults.standard.bool(forKey: "LeafReader.experimentalVocabularyDomains")
    }

    var selectedDocumentDomain: VocabularyDocumentDomain {
        session.documentDomain ?? domainDetection?.suggestedDomain ?? .general
    }

    init(
        documentSource: any VocabularyPreparationDocumentSource,
        library: any VocabularyPreparationLibraryAccess,
        definitionProvider: any VocabularyPreparationDefinitionProviding = LiveVocabularyPreparationDefinitionProvider(),
        readerPriorStore: any VocabularyReaderPriorStoring = VocabularyReaderPriorStore.shared,
        researchEvidenceStore: any VocabularyResearchEvidenceStoring = VocabularyResearchEvidenceStore.shared
    ) {
        self.documentSource = documentSource
        self.library = library
        self.definitionProvider = definitionProvider
        self.readerPriorStore = readerPriorStore
        self.researchEvidenceStore = researchEvidenceStore
    }

    var currentContext: String {
        currentCandidate.flatMap { contexts[$0.canonicalKey] } ?? ""
    }

    var answeredCount: Int { assessment?.answeredQuestionCount ?? 0 }
    var hasSavedAnswers: Bool { !session.answers.isEmpty }
    var predictionAudit: VocabularyPredictionAuditSession? { session.predictionAudit }
    var currentPredictionAuditItem: VocabularyPredictionAuditItem? {
        session.predictionAudit?.nextItem
    }
    var predictionAuditResult: VocabularyPredictionAuditResult? {
        session.predictionAudit?.result()
    }
    var hasCompatiblePredictionAudit: Bool {
        guard let audit = session.predictionAudit, let inventory else { return false }
        return audit.isCompatible(inventory: inventory, mode: mode)
    }

    var predictionAuditProgressText: String {
        guard let audit = session.predictionAudit else { return "0 / 0" }
        return "\(audit.answeredCount) / \(audit.totalCount)"
    }

    var questionLimitText: String {
        "\(answeredCount) / 80"
    }

    func resetForCurrentDocument() {
        cancel()
        inventory = nil
        currentCandidate = nil
        definitionState = .hidden
        interactionState = .awaitingAnswer
        results = nil
        selectedKeys = []
        contexts = [:]
        definitions = [:]
        definitionFailures = [:]
        revealedDefinitionKey = nil
        activeIdentity = nil
        activeDocumentKind = nil
        sourceTexts = []
        readerPrior = nil
        domainDetection = nil
        phase = .welcome
        progressText = ""
        typedMeaningDraft = ""
        assessmentUpdatePending = false
        continueAfterPendingAssessmentUpdate = false
        isPreparingNextQuestion = false
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

    func selectDocumentDomain(_ domain: VocabularyDocumentDomain) {
        guard experimentalDomainsEnabled else { return }
        session.documentDomain = domain
        sessionStore?.save(session)
        guard let inventory else { return }
        self.inventory = DocumentVocabularyInventory(
            languageCode: inventory.languageCode,
            candidates: inventory.candidates,
            excludedCount: inventory.excludedCount,
            documentDomain: domain
        )
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
                    analysisStartedAt: analysisStartedAt,
                    sourceSnapshotMilliseconds: (
                        ProcessInfo.processInfo.systemUptime - analysisStartedAt
                    ) * 1_000
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
        let readerPrior = readerPrior
        if session.readerPriorContributionID == nil {
            session.readerPriorContributionID = UUID().uuidString
            sessionStore?.save(session)
        }
        Task.detached { [weak self] in
            let initializationStartedAt = ProcessInfo.processInfo.systemUptime
            let assessment = AdaptiveVocabularyAssessment(
                inventory: inventory,
                mode: mode,
                restoredAnswers: restored,
                readerPrior: readerPrior
            )
            let advance = Self.advance(
                assessment,
                mutation: .none,
                initializationMilliseconds: (
                    ProcessInfo.processInfo.systemUptime - initializationStartedAt
                ) * 1_000
            )
            await self?.apply(advance: advance, requestID: activeRequestID, persistAnswers: false)
        }
    }

    func beginPredictionAudit() {
        guard let inventory else { return }
        if let audit = session.predictionAudit,
           audit.isCompatible(inventory: inventory, mode: mode) {
            phase = audit.isComplete ? .predictionAuditResults : .predictionAudit
            return
        }
        phase = .analyzing
        progressText = AppText.localized(
            "正在冻结无测试预测…",
            "Freezing the no-assessment prediction…"
        )
        let activeRequestID = requestID
        let mode = mode
        Task.detached { [weak self] in
            let prediction = AdaptiveVocabularyAssessment(
                inventory: inventory,
                mode: mode,
                readerPrior: nil
            ).result()
            let audit = VocabularyPredictionAuditSession(
                inventory: inventory,
                prediction: prediction,
                mode: mode
            )
            await self?.applyPredictionAudit(audit, requestID: activeRequestID)
        }
    }

    func recordPredictionAudit(_ answer: VocabularyPredictionAuditAnswer) {
        guard phase == .predictionAudit,
              let key = session.predictionAudit?.nextItem?.canonicalKey else { return }
        session.predictionAudit?.record(answer, for: key)
        sessionStore?.save(session)
        if session.predictionAudit?.isComplete == true {
            phase = .predictionAuditResults
        }
    }

    func resetPredictionAudit() {
        session.predictionAudit = nil
        sessionStore?.save(session)
        phase = inventory == nil ? .welcome : .inventory
    }

    func returnToInventoryFromPredictionAudit() {
        phase = inventory == nil ? .welcome : .inventory
    }

    func resetAssessment() {
        requestID = UUID()
        clearKnownAdvancePrecomputation()
        definitionTask?.cancel()
        definitionTask = nil
        assessment = nil
        currentCandidate = nil
        definitionState = .hidden
        interactionState = .awaitingAnswer
        results = nil
        selectedKeys = []
        definitions = [:]
        definitionFailures = [:]
        revealedDefinitionKey = nil
        typedMeaningDraft = ""
        assessmentUpdatePending = false
        continueAfterPendingAssessmentUpdate = false
        isPreparingNextQuestion = false
        session.answers = []
        session.finalSelection = []
        session.readerPriorContributionRecorded = false
        session.readerPriorContributionID = nil
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

    func chooseKnown() {
        guard interactionState == .awaitingAnswer, currentCandidate != nil else { return }
        clearKnownAdvancePrecomputation()
        interactionState = .pendingKnownVerification
        revealCurrentQuestion()
        if case .available = definitionState {
            beginKnownAdvancePrecomputation()
        }
    }

    func chooseReportedUnknown() {
        recordEvidenceAndReveal(.reportedUnknown)
    }

    func chooseUnsure() {
        recordEvidenceAndReveal(.unsure)
    }

    func verifyKnown(correct: Bool) {
        guard interactionState == .pendingKnownVerification,
              case .available = definitionState,
              let key = currentCandidate?.canonicalKey else { return }
        let typedMeaning = typedModeEnabled
            ? typedMeaningDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let score = VocabularyPendingKnownScore(
            canonicalKey: key,
            evidence: correct
                ? (typedMeaning.isEmpty ? .verifiedKnown : .typedVerifiedKnown)
                : .verifiedUnknownOrPartial,
            typedMeaning: typedMeaning.isEmpty ? nil : typedMeaning
        )
        if correct,
           precomputedKnownScore == score,
           let advance = precomputedKnownAdvance {
            clearKnownAdvancePrecomputation()
            apply(advance: advance, requestID: requestID, persistAnswers: true)
            return
        }
        if correct, knownAdvanceTask != nil {
            pendingKnownScore = score
            isPreparingNextQuestion = true
            return
        }
        clearKnownAdvancePrecomputation()
        advanceAssessment(
            .score(score.evidence, key, typedMeaning: score.typedMeaning),
            persistAnswers: true
        )
    }

    func continueAfterLearning() {
        guard interactionState == .learningAfterAnswer else { return }
        if assessmentUpdatePending {
            continueAfterPendingAssessmentUpdate = true
            isPreparingNextQuestion = true
            return
        }
        advanceAssessment(.none, persistAnswers: false)
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
        if interactionState == .learningAfterAnswer {
            continueAfterLearning()
        } else {
            clearKnownAdvancePrecomputation()
            advanceAssessment(.skipQuestion, persistAnswers: false)
        }
    }

    func score(_ evidence: VocabularyKnowledgeEvidence) {
        guard evidence != .excluded, case .available = definitionState,
              let key = currentCandidate?.canonicalKey else { return }
        advanceAssessment(.score(evidence, key, typedMeaning: nil), persistAnswers: true)
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
            let definitionBatchStartedAt = ProcessInfo.processInfo.systemUptime
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
            let definitionBatchMilliseconds = (
                ProcessInfo.processInfo.systemUptime - definitionBatchStartedAt
            ) * 1_000
            let resolvedMissingCount = missing.reduce(0) { count, candidate in
                count + (resolved[candidate.canonicalKey] == nil ? 0 : 1)
            }
            ReaderPerformance.record(
                .vocabularyPreparationDefinitionBatch,
                milliseconds: definitionBatchMilliseconds
            )
            ReaderPerformance.logVocabularyPreparation(
                .definitionBatch,
                milliseconds: definitionBatchMilliseconds,
                itemCount: missing.count,
                auxiliaryCount: resolvedMissingCount
            )
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
        clearKnownAdvancePrecomputation()
        assessmentUpdatePending = false
        continueAfterPendingAssessmentUpdate = false
        isPreparingNextQuestion = false
    }

    private func clearKnownAdvancePrecomputation() {
        knownAdvanceTask?.cancel()
        knownAdvanceTask = nil
        precomputedKnownAdvance = nil
        precomputedKnownScore = nil
        pendingKnownScore = nil
        isKnownAnswerPrepared = false
    }

    private func applyPredictionAudit(
        _ audit: VocabularyPredictionAuditSession,
        requestID activeRequestID: UUID
    ) {
        guard requestID == activeRequestID,
              let inventory,
              audit.isCompatible(inventory: inventory, mode: mode),
              let identity = activeIdentity,
              documentSource?.acceptsVocabularyPreparationIdentity(identity) == true else { return }
        session.predictionAudit = audit
        sessionStore?.save(session)
        phase = audit.totalCount == 0
            ? .error(AppText.localized("没有可盲测的词元。", "There are no assessable lemmas to audit."))
            : audit.isComplete ? .predictionAuditResults : .predictionAudit
    }

    private func buildPayload(
        snapshot: VocabularyPreparationSourceSnapshot,
        requestID: UUID,
        cancellationToken: VocabularyPreparationCancellationToken,
        analysisStartedAt: TimeInterval,
        sourceSnapshotMilliseconds: Double
    ) {
        let domainsEnabled = experimentalDomainsEnabled
        let restoredDomain = session.documentDomain
        let priorStore = readerPriorStore
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard !cancellationToken.isCancelled else { return }
            let inventoryModelStartedAt = ProcessInfo.processInfo.systemUptime
            let summaries = snapshot.index.lemmaSummaries()
            let difficultyProvider = DocumentVocabularyFrequencyProvider.calibrated(
                languageCode: snapshot.language.rawValue
            )
            let inventory = DocumentVocabularyInventory(
                summaries: summaries,
                languageCode: snapshot.language.rawValue,
                difficultyProvider: difficultyProvider
            )
            let domainDetection: VocabularyDocumentDomainDetection?
            if domainsEnabled {
                domainDetection = VocabularyDocumentDomainResources.detector.detect(
                    summaries: summaries,
                    languageCode: snapshot.language.rawValue
                )
            } else {
                domainDetection = nil
            }
            let selectedDomain = restoredDomain
                ?? domainDetection?.suggestedDomain
                ?? .general
            let domainInventory = DocumentVocabularyInventory(
                languageCode: inventory.languageCode,
                candidates: inventory.candidates,
                excludedCount: inventory.excludedCount,
                documentDomain: selectedDomain
            )
            let inventoryModelMilliseconds = (
                ProcessInfo.processInfo.systemUptime - inventoryModelStartedAt
            ) * 1_000
            guard !cancellationToken.isCancelled else { return }
            let contextStartedAt = ProcessInfo.processInfo.systemUptime
            let contexts = Dictionary(uniqueKeysWithValues: domainInventory.candidates.map { candidate in
                (candidate.canonicalKey, Self.context(for: candidate.representativeRange, texts: snapshot.texts))
            })
            let contextMaterializationMilliseconds = (
                ProcessInfo.processInfo.systemUptime - contextStartedAt
            ) * 1_000
            let payload = VocabularyPreparationInventoryPayload(
                inventory: domainInventory,
                domainDetection: domainDetection,
                contexts: contexts,
                sourceTexts: snapshot.texts,
                readerPrior: priorStore.load(languageCode: snapshot.language.rawValue),
                sourceSnapshotMilliseconds: sourceSnapshotMilliseconds,
                inventoryModelMilliseconds: inventoryModelMilliseconds,
                contextMaterializationMilliseconds: contextMaterializationMilliseconds
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
        domainDetection = payload.domainDetection
        contexts = payload.contexts
        sourceTexts = payload.sourceTexts
        readerPrior = payload.readerPrior
        alreadySavedKeys = existingVocabularyKeys()
        phase = .inventory
        progressText = AppText.localized(
            "找到 \(payload.inventory.candidates.count) 个可测试词元。",
            "Found \(payload.inventory.candidates.count) assessable lemmas."
        )
        ReaderPerformance.record(
            .vocabularyPreparationSourceSnapshot,
            milliseconds: payload.sourceSnapshotMilliseconds
        )
        ReaderPerformance.record(
            .vocabularyPreparationInventoryModelBuild,
            milliseconds: payload.inventoryModelMilliseconds
        )
        ReaderPerformance.record(
            .vocabularyPreparationContextMaterialization,
            milliseconds: payload.contextMaterializationMilliseconds
        )
        ReaderPerformance.record(.vocabularyPreparationInventoryBuild, milliseconds: durationMilliseconds)
        ReaderPerformance.logVocabularyPreparation(
            .inventory,
            milliseconds: durationMilliseconds,
            itemCount: payload.inventory.candidates.count,
            auxiliaryCount: payload.inventory.excludedCount
        )
        ReaderPerformance.recordMainThreadWork(startedAt: mainWorkStartedAt)
    }

    private func recordEvidenceAndReveal(_ evidence: VocabularyKnowledgeEvidence) {
        guard interactionState == .awaitingAnswer, let key = currentCandidate?.canonicalKey else { return }
        advanceAssessment(
            .score(evidence, key, typedMeaning: nil),
            persistAnswers: true,
            holdCurrent: true,
            revealWhileUpdating: true
        )
    }

    private func advanceAssessment(
        _ mutation: VocabularyAssessmentMutation,
        persistAnswers: Bool,
        holdCurrent: Bool = false,
        revealWhileUpdating: Bool = false
    ) {
        guard let assessment else { return }
        let heldCandidate = holdCurrent ? currentCandidate : nil
        if revealWhileUpdating, heldCandidate != nil {
            assessmentUpdatePending = true
            continueAfterPendingAssessmentUpdate = false
            isPreparingNextQuestion = false
            interactionState = .learningAfterAnswer
            phase = .assessment
            revealCurrentQuestion()
        } else {
            definitionTask?.cancel()
            definitionTask = nil
            revealedDefinitionKey = nil
            phase = .analyzing
            progressText = AppText.localized("正在更新估计…", "Updating the estimate…")
            currentCandidate = nil
            definitionState = .hidden
        }
        let activeRequestID = requestID
        Task.detached { [weak self] in
            let advance = Self.advance(
                assessment,
                mutation: mutation,
                heldCandidate: heldCandidate
            )
            await self?.apply(
                advance: advance,
                requestID: activeRequestID,
                persistAnswers: persistAnswers
            )
        }
    }

    nonisolated private static func advance(
        _ assessment: AdaptiveVocabularyAssessment,
        mutation: VocabularyAssessmentMutation,
        heldCandidate: DocumentVocabularyCandidate? = nil,
        initializationMilliseconds: Double = 0
    ) -> VocabularyAssessmentAdvance {
        let startedAt = ProcessInfo.processInfo.systemUptime
        var assessment = assessment
        let mutationStartedAt = ProcessInfo.processInfo.systemUptime
        switch mutation {
        case .none:
            break
        case let .score(evidence, key, typedMeaning):
            assessment.record(evidence, for: key, typedMeaning: typedMeaning)
        case let .exclude(key):
            assessment.record(.excluded, for: key)
        case .skipQuestion:
            assessment.skipCurrentQuestion()
        }
        let posteriorUpdateMilliseconds = (
            ProcessInfo.processInfo.systemUptime - mutationStartedAt
        ) * 1_000
        if let heldCandidate {
            return VocabularyAssessmentAdvance(
                assessment: assessment,
                candidate: heldCandidate,
                result: nil,
                durationMilliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000,
                initializationMilliseconds: initializationMilliseconds,
                posteriorUpdateMilliseconds: posteriorUpdateMilliseconds,
                nextQuestionMilliseconds: 0,
                resultBuildMilliseconds: 0,
                holdsAnsweredCandidate: true
            )
        }
        if assessment.isFinished {
            let resultStartedAt = ProcessInfo.processInfo.systemUptime
            let result = assessment.result()
            return VocabularyAssessmentAdvance(
                assessment: assessment,
                candidate: nil,
                result: result,
                durationMilliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000,
                initializationMilliseconds: initializationMilliseconds,
                posteriorUpdateMilliseconds: posteriorUpdateMilliseconds,
                nextQuestionMilliseconds: 0,
                resultBuildMilliseconds: (
                    ProcessInfo.processInfo.systemUptime - resultStartedAt
                ) * 1_000,
                holdsAnsweredCandidate: false
            )
        }
        let nextQuestionStartedAt = ProcessInfo.processInfo.systemUptime
        let candidate = assessment.nextQuestion()
        let nextQuestionMilliseconds = (
            ProcessInfo.processInfo.systemUptime - nextQuestionStartedAt
        ) * 1_000
        let resultStartedAt = ProcessInfo.processInfo.systemUptime
        let result = candidate == nil ? assessment.result() : nil
        return VocabularyAssessmentAdvance(
            assessment: assessment,
            candidate: candidate,
            result: result,
            durationMilliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000,
            initializationMilliseconds: initializationMilliseconds,
            posteriorUpdateMilliseconds: posteriorUpdateMilliseconds,
            nextQuestionMilliseconds: nextQuestionMilliseconds,
            resultBuildMilliseconds: result == nil
                ? 0
                : (ProcessInfo.processInfo.systemUptime - resultStartedAt) * 1_000,
            holdsAnsweredCandidate: false
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
        if advance.initializationMilliseconds > 0 {
            ReaderPerformance.record(
                .vocabularyAssessmentInitialization,
                milliseconds: advance.initializationMilliseconds
            )
            ReaderPerformance.logVocabularyPreparation(
                .assessmentInitialization,
                milliseconds: advance.initializationMilliseconds,
                itemCount: inventory?.candidates.count ?? 0
            )
        }
        ReaderPerformance.record(
            .vocabularyAssessmentPosteriorUpdate,
            milliseconds: advance.posteriorUpdateMilliseconds
        )
        if advance.nextQuestionMilliseconds > 0 {
            ReaderPerformance.record(
                .vocabularyAssessmentNextQuestion,
                milliseconds: advance.nextQuestionMilliseconds
            )
        }
        if advance.resultBuildMilliseconds > 0 {
            ReaderPerformance.record(
                .vocabularyAssessmentResultBuild,
                milliseconds: advance.resultBuildMilliseconds
            )
            ReaderPerformance.logVocabularyPreparation(
                .assessmentResults,
                milliseconds: advance.resultBuildMilliseconds,
                itemCount: inventory?.candidates.count ?? 0,
                auxiliaryCount: advance.assessment.answeredQuestionCount
            )
        } else if advance.durationMilliseconds >= 100 {
            ReaderPerformance.logVocabularyPreparation(
                .assessmentAdvance,
                outcome: .slow,
                milliseconds: advance.durationMilliseconds,
                itemCount: inventory?.candidates.count ?? 0,
                auxiliaryCount: advance.assessment.answeredQuestionCount
            )
        }
        ReaderPerformance.record(.vocabularyAssessmentAdvance, milliseconds: advance.durationMilliseconds)
        assessment = advance.assessment
        if persistAnswers { persistAssessment() }
        if advance.holdsAnsweredCandidate, assessmentUpdatePending {
            assessmentUpdatePending = false
            let shouldContinue = continueAfterPendingAssessmentUpdate
            continueAfterPendingAssessmentUpdate = false
            isPreparingNextQuestion = false
            if shouldContinue {
                advanceAssessment(.none, persistAnswers: false)
            } else {
                phase = .assessment
                interactionState = .learningAfterAnswer
                if definitionState == .hidden { revealCurrentQuestion() }
            }
            return
        }
        if let result = advance.result {
            showResults(result)
            return
        }
        currentCandidate = advance.candidate
        definitionState = .hidden
        phase = .assessment
        if let candidate = advance.candidate {
            prefetchDefinition(for: candidate)
            if advance.holdsAnsweredCandidate {
                interactionState = .learningAfterAnswer
                revealCurrentQuestion()
            } else {
                interactionState = .awaitingAnswer
                typedMeaningDraft = ""
            }
        }
    }

    private func beginKnownAdvancePrecomputation() {
        guard knownAdvanceTask == nil,
              precomputedKnownAdvance == nil,
              interactionState == .pendingKnownVerification,
              let assessment,
              let candidate = currentCandidate,
              let identity = activeIdentity else { return }
        let typedMeaning = typedModeEnabled
            ? typedMeaningDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let score = VocabularyPendingKnownScore(
            canonicalKey: candidate.canonicalKey,
            evidence: typedMeaning.isEmpty ? .verifiedKnown : .typedVerifiedKnown,
            typedMeaning: typedMeaning.isEmpty ? nil : typedMeaning
        )
        let activeRequestID = requestID
        knownAdvanceTask = Task.detached(priority: .userInitiated) { [weak self] in
            let advance = Self.advance(
                assessment,
                mutation: .score(
                    score.evidence,
                    score.canonicalKey,
                    typedMeaning: score.typedMeaning
                )
            )
            guard !Task.isCancelled else { return }
            await self?.receiveKnownAdvance(
                advance,
                score: score,
                identity: identity,
                requestID: activeRequestID
            )
        }
    }

    private func receiveKnownAdvance(
        _ advance: VocabularyAssessmentAdvance,
        score: VocabularyPendingKnownScore,
        identity: VocabularyPreparationDocumentIdentity,
        requestID activeRequestID: UUID
    ) {
        guard requestID == activeRequestID,
              documentSource?.acceptsVocabularyPreparationIdentity(identity) == true,
              currentCandidate?.canonicalKey == score.canonicalKey,
              interactionState == .pendingKnownVerification else { return }
        ReaderPerformance.record(
            .vocabularyAssessmentKnownPrecomputation,
            milliseconds: advance.durationMilliseconds
        )
        if advance.durationMilliseconds >= 100 {
            ReaderPerformance.logVocabularyPreparation(
                .assessmentPrecomputation,
                outcome: .slow,
                milliseconds: advance.durationMilliseconds,
                itemCount: inventory?.candidates.count ?? 0,
                auxiliaryCount: advance.assessment.answeredQuestionCount
            )
        }
        knownAdvanceTask = nil
        if pendingKnownScore == score {
            pendingKnownScore = nil
            isPreparingNextQuestion = false
            apply(advance: advance, requestID: activeRequestID, persistAnswers: true)
        } else {
            precomputedKnownAdvance = advance
            precomputedKnownScore = score
            isKnownAnswerPrepared = true
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
            let lookupStartedAt = ProcessInfo.processInfo.systemUptime
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
                let lookupMilliseconds = (
                    ProcessInfo.processInfo.systemUptime - lookupStartedAt
                ) * 1_000
                ReaderPerformance.record(
                    .vocabularyDefinitionLookup,
                    milliseconds: lookupMilliseconds
                )
                if lookupMilliseconds >= 500 {
                    ReaderPerformance.logVocabularyPreparation(
                        .definitionLookup,
                        outcome: .slow,
                        milliseconds: lookupMilliseconds
                    )
                }
                self.definitions[key] = definition
                self.definitionTask = nil
                if self.revealedDefinitionKey == key {
                    self.definitionState = .available(definition.markdown)
                    if self.interactionState == .pendingKnownVerification {
                        self.beginKnownAdvancePrecomputation()
                    }
                }
            } catch {
                guard !Task.isCancelled, let self,
                      self.requestID == activeRequestID,
                      self.currentCandidate?.canonicalKey == key,
                      self.documentSource?.acceptsVocabularyPreparationIdentity(identity) == true else { return }
                let lookupMilliseconds = (
                    ProcessInfo.processInfo.systemUptime - lookupStartedAt
                ) * 1_000
                ReaderPerformance.record(
                    .vocabularyDefinitionLookup,
                    milliseconds: lookupMilliseconds
                )
                ReaderPerformance.logVocabularyPreparation(
                    .definitionLookup,
                    outcome: .failed,
                    milliseconds: lookupMilliseconds
                )
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
        recordReaderPriorContributionIfNeeded()
    }

    private func recordReaderPriorContributionIfNeeded() {
        guard session.readerPriorContributionRecorded != true,
              let contributionID = session.readerPriorContributionID,
              let assessment,
              assessment.answeredQuestionCount > 0,
              let inventory else { return }
        let languageCode = inventory.languageCode
        let posterior = assessment.thetaPosteriorSnapshot
        let verifiedCount = assessment.verifiedEvidenceCount
        let store = readerPriorStore
        let researchStore = researchEvidenceStore
        let answers = assessment.answers
        let activeRequestID = requestID
        Task { [weak self] in
            let saved = await Task.detached {
                let priorSaved = store.recordCompletedSession(
                    contributionID: contributionID,
                    languageCode: languageCode,
                    thetaPosterior: posterior,
                    verifiedEvidenceCount: verifiedCount,
                    completedAt: Date(),
                    algorithmVersion: VocabularyPreparationSession.currentAlgorithmVersion
                )
                _ = researchStore.recordCompletedSession(
                    contributionID: contributionID,
                    inventory: inventory,
                    answers: answers,
                    protocolVersion: VocabularyPreparationSession.currentAlgorithmVersion
                )
                return priorSaved
            }.value
            guard saved else { return }
            guard let self, self.requestID == activeRequestID else { return }
            self.session.readerPriorContributionRecorded = true
            self.sessionStore?.save(self.session)
        }
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
        let persistedKeys = library.vocabularyPreparationExistingKeys(
            language: NLLanguage(rawValue: languageCode),
            kind: kind
        )
        guard let inventory else { return persistedKeys }
        return Set(inventory.candidates.compactMap { candidate in
            persistedKeys.contains(candidate.canonicalKey) || persistedKeys.contains(candidate.lemmaKey)
                ? candidate.canonicalKey
                : nil
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
        identity: VocabularyPreparationDocumentIdentity,
        requestID: UUID,
        importStartedAt: TimeInterval
    ) async {
        guard let library, let kind = activeDocumentKind,
              self.requestID == requestID,
              documentSource?.acceptsVocabularyPreparationIdentity(identity) == true else { return }
        self.definitions = definitions
        let materializationStartedAt = ProcessInfo.processInfo.systemUptime
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
                    lexicalKey: candidate.canonicalKey,
                    partOfSpeech: candidate.partOfSpeech,
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
                    lexicalKey: candidate.canonicalKey,
                    partOfSpeech: candidate.partOfSpeech,
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
        let materializationMilliseconds = (
            ProcessInfo.processInfo.systemUptime - materializationStartedAt
        ) * 1_000
        ReaderPerformance.record(
            .vocabularyPreparationImportMaterialization,
            milliseconds: materializationMilliseconds
        )
        let persistenceStartedAt = ProcessInfo.processInfo.systemUptime
        let didPersist = await library.persistVocabularyPreparationBatch(batch, documentID: identity.documentID)
        guard self.requestID == requestID,
              documentSource?.acceptsVocabularyPreparationIdentity(identity) == true else { return }
        let persistenceMilliseconds = (
            ProcessInfo.processInfo.systemUptime - persistenceStartedAt
        ) * 1_000
        ReaderPerformance.record(
            .vocabularyPreparationImportPersistence,
            milliseconds: persistenceMilliseconds
        )
        let importMilliseconds = (
            ProcessInfo.processInfo.systemUptime - importStartedAt
        ) * 1_000
        ReaderPerformance.record(
            .vocabularyPreparationImport,
            milliseconds: importMilliseconds
        )
        ReaderPerformance.logVocabularyPreparation(
            .importRecords,
            outcome: didPersist ? .completed : .failed,
            milliseconds: importMilliseconds,
            itemCount: batch.count,
            auxiliaryCount: batch.unresolvedDefinitions.count
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
