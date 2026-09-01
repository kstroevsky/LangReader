import Foundation
import NaturalLanguage
import XCTest
import LeafReaderCore
@testable import LeafReaderApp

@MainActor
final class VocabularyPreparationCoordinatorXCTests: XCTestCase {
    private let fixtureText = "They develop tools. She developed one while developing another. Development continues. Readers learn vocabulary."
    private let readerPriorStore = FakeVocabularyReaderPriorStore()
    private let researchEvidenceStore = FakeVocabularyResearchEvidenceStore()

    func testPDFAndWebSnapshotsProduceEquivalentInventories() async throws {
        let text = fixtureText
        let pdfSource = try FakeVocabularyPreparationSource(text: text, kind: .pdf)
        let webSource = try FakeVocabularyPreparationSource(text: text, kind: .epub)
        let pdfLibrary = FakeVocabularyPreparationLibrary()
        let webLibrary = FakeVocabularyPreparationLibrary()
        let provider = FakeVocabularyPreparationDefinitionProvider()
        let pdf = VocabularyPreparationCoordinator(
            documentSource: pdfSource,
            library: pdfLibrary,
            definitionProvider: provider,
            readerPriorStore: readerPriorStore,
            researchEvidenceStore: researchEvidenceStore
        )
        let web = VocabularyPreparationCoordinator(
            documentSource: webSource,
            library: webLibrary,
            definitionProvider: provider,
            readerPriorStore: readerPriorStore,
            researchEvidenceStore: researchEvidenceStore
        )

        pdf.resetForCurrentDocument()
        web.resetForCurrentDocument()
        pdf.startAnalysis()
        web.startAnalysis()
        try await waitUntil { pdf.phase == .inventory && web.phase == .inventory }

        XCTAssertGreaterThan(pdfSource.lemmaSummaryCount, 0)
        XCTAssertNotEqual(pdfSource.lemmaNameFlags.values.filter { $0 }.count, pdfSource.lemmaSummaryCount)
        XCTAssertGreaterThan(pdf.inventory?.candidates.count ?? 0, 0)
        XCTAssertEqual(
            pdf.inventory?.candidates.map { "\($0.canonicalKey):\($0.occurrenceCount)" },
            web.inventory?.candidates.map { "\($0.canonicalKey):\($0.occurrenceCount)" }
        )
    }

    func testStaleSnapshotNeverPublishesInventory() async throws {
        let source = try FakeVocabularyPreparationSource(
            text: fixtureText,
            kind: .docx,
            snapshotDelayNanoseconds: 80_000_000
        )
        let library = FakeVocabularyPreparationLibrary()
        let coordinator = VocabularyPreparationCoordinator(
            documentSource: source,
            library: library,
            definitionProvider: FakeVocabularyPreparationDefinitionProvider(),
            readerPriorStore: readerPriorStore,
            researchEvidenceStore: researchEvidenceStore
        )
        coordinator.resetForCurrentDocument()
        coordinator.startAnalysis()
        source.advanceGeneration()

        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertNil(coordinator.inventory)
        XCTAssertNotEqual(coordinator.phase, .inventory)
    }

    func testPrefetchStaysHiddenUntilRevealAndRetryRecovers() async throws {
        let source = try FakeVocabularyPreparationSource(
            text: fixtureText,
            kind: .epub
        )
        let library = FakeVocabularyPreparationLibrary()
        let provider = FakeVocabularyPreparationDefinitionProvider(failFirstRequest: true)
        let coordinator = VocabularyPreparationCoordinator(
            documentSource: source,
            library: library,
            definitionProvider: provider,
            readerPriorStore: readerPriorStore,
            researchEvidenceStore: researchEvidenceStore
        )
        coordinator.resetForCurrentDocument()
        coordinator.startAnalysis()
        try await waitUntil { coordinator.phase == .inventory }
        coordinator.beginAssessment()
        try await waitUntil { coordinator.phase == .assessment }
        try await waitUntil { await provider.requestCount() == 1 }

        XCTAssertEqual(coordinator.definitionState, .hidden)
        coordinator.revealCurrentQuestion()
        try await waitUntil {
            if case .unavailable = coordinator.definitionState { return true }
            return false
        }
        coordinator.retryDefinition()
        try await waitUntil {
            if case .available = coordinator.definitionState { return true }
            return false
        }
        let requestCount = await provider.requestCount()
        XCTAssertEqual(requestCount, 2)
    }

    func testSkipMovesOnWithoutConsumingAnsweredSlot() async throws {
        let source = try FakeVocabularyPreparationSource(
            text: fixtureText,
            kind: .pdf
        )
        let coordinator = VocabularyPreparationCoordinator(
            documentSource: source,
            library: FakeVocabularyPreparationLibrary(),
            definitionProvider: FakeVocabularyPreparationDefinitionProvider(),
            readerPriorStore: readerPriorStore,
            researchEvidenceStore: researchEvidenceStore
        )
        coordinator.resetForCurrentDocument()
        coordinator.startAnalysis()
        try await waitUntil { coordinator.phase == .inventory }
        coordinator.beginAssessment()
        try await waitUntil { coordinator.phase == .assessment }
        let firstKey = try XCTUnwrap(coordinator.currentCandidate?.canonicalKey)

        coordinator.skipDefinition()
        try await waitUntil {
            coordinator.phase == .assessment && coordinator.currentCandidate?.canonicalKey != firstKey
        }
        XCTAssertEqual(coordinator.answeredCount, 0)
    }

    func testKnownAnswerDoesNotCountUntilVerifiedAfterReveal() async throws {
        let source = try FakeVocabularyPreparationSource(text: fixtureText, kind: .pdf)
        let coordinator = VocabularyPreparationCoordinator(
            documentSource: source,
            library: FakeVocabularyPreparationLibrary(),
            definitionProvider: FakeVocabularyPreparationDefinitionProvider(),
            readerPriorStore: readerPriorStore,
            researchEvidenceStore: researchEvidenceStore
        )
        coordinator.resetForCurrentDocument()
        coordinator.startAnalysis()
        try await waitUntil { coordinator.phase == .inventory }
        coordinator.beginAssessment()
        try await waitUntil { coordinator.phase == .assessment }

        coordinator.chooseKnown()
        XCTAssertEqual(coordinator.interactionState, .pendingKnownVerification)
        XCTAssertEqual(coordinator.answeredCount, 0)
        try await waitUntil {
            if case .available = coordinator.definitionState { return true }
            return false
        }
        XCTAssertEqual(coordinator.answeredCount, 0)
        coordinator.verifyKnown(correct: true)
        try await waitUntil { coordinator.answeredCount == 1 && coordinator.phase == .assessment }
    }

    func testVerifiedKnownUsesExactPrecomputedAdvanceWhenReady() async throws {
        let source = try FakeVocabularyPreparationSource(text: fixtureText, kind: .pdf)
        let coordinator = VocabularyPreparationCoordinator(
            documentSource: source,
            library: FakeVocabularyPreparationLibrary(),
            definitionProvider: FakeVocabularyPreparationDefinitionProvider(),
            readerPriorStore: readerPriorStore,
            researchEvidenceStore: researchEvidenceStore
        )
        coordinator.resetForCurrentDocument()
        coordinator.startAnalysis()
        try await waitUntil { coordinator.phase == .inventory }
        coordinator.beginAssessment()
        try await waitUntil { coordinator.phase == .assessment }
        let firstKey = try XCTUnwrap(coordinator.currentCandidate?.canonicalKey)

        coordinator.chooseKnown()
        try await waitUntil {
            if case .available = coordinator.definitionState {
                return coordinator.isKnownAnswerPrepared
            }
            return false
        }
        XCTAssertEqual(coordinator.answeredCount, 0)

        coordinator.verifyKnown(correct: true)

        XCTAssertEqual(coordinator.answeredCount, 1)
        XCTAssertEqual(coordinator.phase, .assessment)
        XCTAssertNotEqual(coordinator.currentCandidate?.canonicalKey, firstKey)
        XCTAssertFalse(coordinator.isPreparingNextQuestion)
    }

    func testBlindPredictionAuditBypassesAssessmentAndStaysOutOfProfilesAndResearch() async throws {
        let source = try FakeVocabularyPreparationSource(text: fixtureText, kind: .pdf)
        let priorStore = FakeVocabularyReaderPriorStore()
        let researchStore = FakeVocabularyResearchEvidenceStore()
        let provider = FakeVocabularyPreparationDefinitionProvider()
        let sessionStore = VocabularyPreparationSessionStore(documentID: source.identity.documentID)
        defer { sessionStore.clear() }
        let coordinator = VocabularyPreparationCoordinator(
            documentSource: source,
            library: FakeVocabularyPreparationLibrary(),
            definitionProvider: provider,
            readerPriorStore: priorStore,
            researchEvidenceStore: researchStore
        )
        coordinator.resetForCurrentDocument()
        coordinator.startAnalysis()
        try await waitUntil { coordinator.phase == .inventory }

        coordinator.beginPredictionAudit()
        try await waitUntil { coordinator.phase == .predictionAudit }
        XCTAssertEqual(coordinator.predictionAudit?.totalCount, coordinator.inventory?.candidates.count)
        let firstKey = try XCTUnwrap(coordinator.currentPredictionAuditItem?.canonicalKey)
        coordinator.recordPredictionAudit(.known)
        coordinator.returnToInventoryFromPredictionAudit()
        coordinator.beginPredictionAudit()
        XCTAssertEqual(coordinator.predictionAudit?.answeredCount, 1)
        XCTAssertNotEqual(coordinator.currentPredictionAuditItem?.canonicalKey, firstKey)

        while coordinator.phase == .predictionAudit {
            coordinator.recordPredictionAudit(.unknown)
        }
        XCTAssertEqual(coordinator.phase, .predictionAuditResults)
        XCTAssertNotNil(coordinator.predictionAuditResult)
        XCTAssertEqual(coordinator.answeredCount, 0)
        XCTAssertNil(priorStore.load(languageCode: "en"))
        XCTAssertEqual(researchStore.recordedSessionCount, 0)
        let definitionRequestCount = await provider.requestCount()
        XCTAssertEqual(definitionRequestCount, 0)
        XCTAssertTrue(sessionStore.load()?.predictionAudit?.isComplete == true)
    }

    func testTypedKnownAnswerRemainsPendingUntilSelfVerificationAndPersistsLocally() async throws {
        let source = try FakeVocabularyPreparationSource(text: fixtureText, kind: .pdf)
        let sessionStore = VocabularyPreparationSessionStore(documentID: source.identity.documentID)
        defer { sessionStore.clear() }
        let coordinator = VocabularyPreparationCoordinator(
            documentSource: source,
            library: FakeVocabularyPreparationLibrary(),
            definitionProvider: FakeVocabularyPreparationDefinitionProvider(),
            readerPriorStore: readerPriorStore,
            researchEvidenceStore: researchEvidenceStore
        )
        coordinator.resetForCurrentDocument()
        coordinator.startAnalysis()
        try await waitUntil { coordinator.phase == .inventory }
        coordinator.beginAssessment()
        try await waitUntil { coordinator.phase == .assessment }
        coordinator.typedModeEnabled = true
        coordinator.typedMeaningDraft = "to create or improve over time"

        coordinator.chooseKnown()
        XCTAssertEqual(coordinator.answeredCount, 0)
        try await waitUntil {
            if case .available = coordinator.definitionState { return true }
            return false
        }
        XCTAssertEqual(coordinator.answeredCount, 0)

        coordinator.verifyKnown(correct: true)
        try await waitUntil { coordinator.answeredCount == 1 }
        let answer = try XCTUnwrap(sessionStore.load()?.answers.first)
        XCTAssertEqual(answer.evidence, .typedVerifiedKnown)
        XCTAssertEqual(answer.typedMeaning, "to create or improve over time")
    }

    func testUnknownEvidenceCountsBeforeFailedDefinitionAndSkipOnlyContinues() async throws {
        let source = try FakeVocabularyPreparationSource(text: fixtureText, kind: .epub)
        let provider = FakeVocabularyPreparationDefinitionProvider(failFirstRequest: true)
        let coordinator = VocabularyPreparationCoordinator(
            documentSource: source,
            library: FakeVocabularyPreparationLibrary(),
            definitionProvider: provider,
            readerPriorStore: readerPriorStore,
            researchEvidenceStore: researchEvidenceStore
        )
        coordinator.resetForCurrentDocument()
        coordinator.startAnalysis()
        try await waitUntil { coordinator.phase == .inventory }
        coordinator.beginAssessment()
        try await waitUntil { coordinator.phase == .assessment }
        let firstKey = try XCTUnwrap(coordinator.currentCandidate?.canonicalKey)

        coordinator.chooseReportedUnknown()
        try await waitUntil {
            coordinator.answeredCount == 1 && coordinator.interactionState == .learningAfterAnswer
        }
        try await waitUntil {
            if case .unavailable = coordinator.definitionState { return true }
            return false
        }
        coordinator.skipDefinition()
        try await waitUntil {
            coordinator.phase == .assessment && coordinator.currentCandidate?.canonicalKey != firstKey
        }
        XCTAssertEqual(coordinator.answeredCount, 1)
    }

    func testUnknownAnswerRevealsImmediatelyAndHidesUpdateBehindLearning() async throws {
        let source = try FakeVocabularyPreparationSource(text: fixtureText, kind: .epub)
        let coordinator = VocabularyPreparationCoordinator(
            documentSource: source,
            library: FakeVocabularyPreparationLibrary(),
            definitionProvider: FakeVocabularyPreparationDefinitionProvider(),
            readerPriorStore: readerPriorStore,
            researchEvidenceStore: researchEvidenceStore
        )
        coordinator.resetForCurrentDocument()
        coordinator.startAnalysis()
        try await waitUntil { coordinator.phase == .inventory }
        coordinator.beginAssessment()
        try await waitUntil { coordinator.phase == .assessment }
        let firstKey = try XCTUnwrap(coordinator.currentCandidate?.canonicalKey)

        coordinator.chooseUnsure()

        XCTAssertEqual(coordinator.phase, .assessment)
        XCTAssertEqual(coordinator.interactionState, .learningAfterAnswer)
        XCTAssertEqual(coordinator.answeredCount, 0)
        XCTAssertNotEqual(coordinator.definitionState, .hidden)

        coordinator.continueAfterLearning()
        XCTAssertTrue(coordinator.isPreparingNextQuestion)
        try await waitUntil {
            coordinator.phase == .assessment
                && coordinator.currentCandidate?.canonicalKey != firstKey
        }
        XCTAssertEqual(coordinator.answeredCount, 1)
        XCTAssertFalse(coordinator.isPreparingNextQuestion)
    }

    func testAlreadySavedLemmaIsProtectedAndSuccessfulImportOpensReview() async throws {
        let source = try FakeVocabularyPreparationSource(
            text: fixtureText,
            kind: .epub
        )
        let library = FakeVocabularyPreparationLibrary(existingKeys: ["reader"])
        let coordinator = VocabularyPreparationCoordinator(
            documentSource: source,
            library: library,
            definitionProvider: FakeVocabularyPreparationDefinitionProvider(),
            readerPriorStore: readerPriorStore,
            researchEvidenceStore: researchEvidenceStore
        )
        coordinator.resetForCurrentDocument()
        coordinator.startAnalysis()
        try await waitUntil { coordinator.phase == .inventory }
        let savedReadKey = try XCTUnwrap(
            coordinator.inventory?.candidates.first { $0.lemmaKey == "reader" }?.canonicalKey
        )
        XCTAssertTrue(coordinator.alreadySavedKeys.contains(savedReadKey))

        try await answerEveryAvailableQuestionUnknown(in: coordinator)
        let importable = try XCTUnwrap(
            coordinator.results?.items.first { !coordinator.alreadySavedKeys.contains($0.id) }
        )
        for item in coordinator.results?.items ?? [] {
            coordinator.updateSelection(item.id, selected: false)
        }
        coordinator.updateSelection(importable.id, selected: true)
        coordinator.updateSelection(savedReadKey, selected: true)
        XCTAssertFalse(coordinator.selectedKeys.contains(savedReadKey))

        coordinator.createAndReview()
        try await waitUntil { library.finishedBatchCount == 1 }
        XCTAssertEqual(library.persistedBatchCount, 1)
        XCTAssertEqual(library.lastPersistedDocumentID, source.identity.documentID)
        XCTAssertEqual(library.lastBatch?.count, 1)
    }

    func testImportFailureDoesNotOpenReview() async throws {
        let source = try FakeVocabularyPreparationSource(
            text: fixtureText,
            kind: .pdf
        )
        let library = FakeVocabularyPreparationLibrary(shouldPersist: false)
        let coordinator = VocabularyPreparationCoordinator(
            documentSource: source,
            library: library,
            definitionProvider: FakeVocabularyPreparationDefinitionProvider(),
            readerPriorStore: readerPriorStore,
            researchEvidenceStore: researchEvidenceStore
        )
        coordinator.resetForCurrentDocument()
        coordinator.startAnalysis()
        try await waitUntil { coordinator.phase == .inventory }
        try await answerEveryAvailableQuestionUnknown(in: coordinator)
        let key = try XCTUnwrap(coordinator.results?.items.first?.id)
        coordinator.updateSelection(key, selected: true)

        coordinator.createAndReview()
        try await waitUntil {
            if case .error = coordinator.phase { return true }
            return false
        }
        XCTAssertEqual(library.persistedBatchCount, 1)
        XCTAssertEqual(library.finishedBatchCount, 0)
    }

    func testOnlyCompletedAssessmentUpdatesLocalReaderProfile() async throws {
        let source = try FakeVocabularyPreparationSource(text: fixtureText, kind: .pdf)
        let store = FakeVocabularyReaderPriorStore()
        let researchStore = FakeVocabularyResearchEvidenceStore(shouldRecord: false)
        let coordinator = VocabularyPreparationCoordinator(
            documentSource: source,
            library: FakeVocabularyPreparationLibrary(),
            definitionProvider: FakeVocabularyPreparationDefinitionProvider(),
            readerPriorStore: store,
            researchEvidenceStore: researchStore
        )
        coordinator.resetForCurrentDocument()
        coordinator.startAnalysis()
        try await waitUntil { coordinator.phase == .inventory }
        coordinator.beginAssessment()
        try await waitUntil { coordinator.phase == .assessment }
        XCTAssertNil(store.load(languageCode: "en"))

        try await answerEveryAvailableQuestionUnknown(in: coordinator)
        try await waitUntil { store.load(languageCode: "en")?.completedSessionCount == 1 }
        XCTAssertEqual(store.load(languageCode: "en")?.verifiedEvidenceCount, 0)
        XCTAssertEqual(researchStore.recordedSessionCount, 0)
    }

    private func answerEveryAvailableQuestionUnknown(
        in coordinator: VocabularyPreparationCoordinator
    ) async throws {
        coordinator.beginAssessment()
        while coordinator.phase != .results {
            try await waitUntil { coordinator.phase == .assessment || coordinator.phase == .results }
            if coordinator.phase == .results { break }
            coordinator.revealCurrentQuestion()
            try await waitUntil {
                if case .available = coordinator.definitionState { return true }
                return false
            }
            coordinator.score(.unknown)
        }
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 3_000_000_000,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let start = ContinuousClock.now
        while !(await condition()) {
            if ContinuousClock.now - start > .nanoseconds(Int64(timeoutNanoseconds)) {
                XCTFail("Timed out waiting for coordinator state")
                throw CocoaError(.coderReadCorrupt)
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

@MainActor
private final class FakeVocabularyPreparationSource: VocabularyPreparationDocumentSource {
    private(set) var identity: VocabularyPreparationDocumentIdentity
    private let snapshotTemplate: VocabularyPreparationSourceSnapshot
    private let snapshotDelayNanoseconds: UInt64

    init(
        text: String,
        kind: ReaderDocumentKind,
        snapshotDelayNanoseconds: UInt64 = 0
    ) throws {
        let identity = VocabularyPreparationDocumentIdentity(
            documentID: UUID().uuidString,
            loadGeneration: 1,
            webPlainTextGeneration: kind == .pdf ? nil : 1
        )
        self.identity = identity
        self.snapshotDelayNanoseconds = snapshotDelayNanoseconds
        snapshotTemplate = VocabularyPreparationSourceSnapshot(
            identity: identity,
            kind: kind,
            language: .english,
            texts: [text],
            index: try XCTUnwrap(VocabularyDocumentLemmaIndex(
                texts: [text],
                language: .english,
                maximumWorkerCount: 1
            ))
        )
    }

    var vocabularyPreparationIdentity: VocabularyPreparationDocumentIdentity? { identity }
    var lemmaSummaryCount: Int { snapshotTemplate.index.lemmaSummaries().count }
    var lemmaNameFlags: [String: Bool] {
        Dictionary(uniqueKeysWithValues: snapshotTemplate.index.lemmaSummaries().map {
            ($0.canonicalKey, $0.isConfidentName)
        })
    }

    func vocabularyPreparationSnapshot(
        requestedLanguage: NLLanguage?
    ) async throws -> VocabularyPreparationSourceSnapshot {
        if snapshotDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: snapshotDelayNanoseconds)
        }
        return snapshotTemplate
    }

    func acceptsVocabularyPreparationIdentity(_ identity: VocabularyPreparationDocumentIdentity) -> Bool {
        self.identity == identity
    }

    func advanceGeneration() {
        identity = VocabularyPreparationDocumentIdentity(
            documentID: identity.documentID,
            loadGeneration: identity.loadGeneration + 1,
            webPlainTextGeneration: identity.webPlainTextGeneration.map { $0 + 1 }
        )
    }
}

private actor FakeVocabularyPreparationDefinitionProvider: VocabularyPreparationDefinitionProviding {
    private var calls = 0
    private let failFirstRequest: Bool

    init(failFirstRequest: Bool = false) {
        self.failFirstRequest = failFirstRequest
    }

    func definition(
        for candidate: DocumentVocabularyCandidate,
        languageCode: String,
        context: String
    ) async throws -> VocabularyPreparedDefinition {
        calls += 1
        if failFirstRequest && calls == 1 {
            throw CocoaError(.fileReadUnknown)
        }
        return VocabularyPreparedDefinition(
            markdown: "Definition of \(candidate.displayLemma)",
            tags: nil,
            frequency: candidate.generalFrequencyRank
        )
    }

    func requestCount() -> Int { calls }
}

private final class FakeVocabularyReaderPriorStore: VocabularyReaderPriorStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: VocabularyReaderPrior] = [:]
    private var contributions = Set<String>()

    func load(languageCode: String) -> VocabularyReaderPrior? {
        lock.withLock { values[languageCode] }
    }

    func summaries() -> [VocabularyReaderPriorSummary] {
        lock.withLock {
            values.values.map {
                VocabularyReaderPriorSummary(
                    languageCode: $0.languageCode,
                    completedSessionCount: $0.completedSessionCount,
                    verifiedEvidenceCount: $0.verifiedEvidenceCount,
                    lastUpdatedAt: $0.lastUpdatedAt
                )
            }.sorted { $0.languageCode < $1.languageCode }
        }
    }

    func recordCompletedSession(
        contributionID: String,
        languageCode: String,
        thetaPosterior: [Double],
        verifiedEvidenceCount: Int,
        completedAt: Date,
        algorithmVersion: Int
    ) -> Bool {
        lock.withLock {
            guard contributions.insert(contributionID).inserted else { return }
            let existing = values[languageCode]
            values[languageCode] = VocabularyReaderPrior(
                languageCode: languageCode,
                thetaPosterior: thetaPosterior,
                completedSessionCount: (existing?.completedSessionCount ?? 0) + 1,
                verifiedEvidenceCount: (existing?.verifiedEvidenceCount ?? 0) + verifiedEvidenceCount,
                lastUpdatedAt: completedAt,
                algorithmVersion: algorithmVersion
            )
        }
        return true
    }

    func reset(languageCode: String) -> Bool {
        lock.withLock {
            values[languageCode] = nil
            contributions = []
        }
        return true
    }
}

private final class FakeVocabularyResearchEvidenceStore: VocabularyResearchEvidenceStoring, @unchecked Sendable {
    private let lock = NSLock()
    private let shouldRecord: Bool
    private var contributionIDs = Set<String>()

    init(shouldRecord: Bool = true) {
        self.shouldRecord = shouldRecord
    }

    var recordedSessionCount: Int {
        lock.withLock { contributionIDs.count }
    }

    func recordCompletedSession(
        contributionID: String,
        inventory: DocumentVocabularyInventory,
        answers: [VocabularyAssessmentAnswer],
        protocolVersion: Int
    ) -> Bool {
        guard shouldRecord else { return false }
        lock.withLock {
            _ = contributionIDs.insert(contributionID)
        }
        return true
    }

    func export(profile: VocabularyResearchProfile) -> VocabularyResearchExport {
        VocabularyResearchExport(participant: profile, records: [])
    }

    func recordCount() -> Int { 0 }
}

@MainActor
private final class FakeVocabularyPreparationLibrary: VocabularyPreparationLibraryAccess {
    let existingKeys: Set<String>
    let shouldPersist: Bool
    private(set) var persistedBatchCount = 0
    private(set) var finishedBatchCount = 0
    private(set) var lastBatch: VocabularyPreparationImportBatch?
    private(set) var lastPersistedDocumentID: String?

    init(existingKeys: Set<String> = [], shouldPersist: Bool = true) {
        self.existingKeys = existingKeys
        self.shouldPersist = shouldPersist
    }

    func vocabularyPreparationExistingKeys(language: NLLanguage, kind: ReaderDocumentKind) -> Set<String> {
        existingKeys
    }

    func persistVocabularyPreparationBatch(
        _ batch: VocabularyPreparationImportBatch,
        documentID: String
    ) async -> Bool {
        persistedBatchCount += 1
        lastBatch = batch
        lastPersistedDocumentID = documentID
        return shouldPersist
    }

    func finishVocabularyPreparationImport(_ batch: VocabularyPreparationImportBatch) {
        finishedBatchCount += 1
        lastBatch = batch
    }
}
