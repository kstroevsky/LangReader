import Foundation
import NaturalLanguage
import XCTest
import LeafReaderCore
@testable import LeafReaderApp

@MainActor
final class VocabularyPreparationCoordinatorXCTests: XCTestCase {
    private let fixtureText = "They develop tools. She developed one while developing another. Development continues. Readers learn vocabulary."

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
            definitionProvider: provider
        )
        let web = VocabularyPreparationCoordinator(
            documentSource: webSource,
            library: webLibrary,
            definitionProvider: provider
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
            definitionProvider: FakeVocabularyPreparationDefinitionProvider()
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
            definitionProvider: provider
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
            definitionProvider: FakeVocabularyPreparationDefinitionProvider()
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
            definitionProvider: FakeVocabularyPreparationDefinitionProvider()
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

    func testUnknownEvidenceCountsBeforeFailedDefinitionAndSkipOnlyContinues() async throws {
        let source = try FakeVocabularyPreparationSource(text: fixtureText, kind: .epub)
        let provider = FakeVocabularyPreparationDefinitionProvider(failFirstRequest: true)
        let coordinator = VocabularyPreparationCoordinator(
            documentSource: source,
            library: FakeVocabularyPreparationLibrary(),
            definitionProvider: provider
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

    func testAlreadySavedLemmaIsProtectedAndSuccessfulImportOpensReview() async throws {
        let source = try FakeVocabularyPreparationSource(
            text: fixtureText,
            kind: .epub
        )
        let library = FakeVocabularyPreparationLibrary(existingKeys: ["read"])
        let coordinator = VocabularyPreparationCoordinator(
            documentSource: source,
            library: library,
            definitionProvider: FakeVocabularyPreparationDefinitionProvider()
        )
        coordinator.resetForCurrentDocument()
        coordinator.startAnalysis()
        try await waitUntil { coordinator.phase == .inventory }
        XCTAssertTrue(coordinator.alreadySavedKeys.contains("read"))

        try await answerEveryAvailableQuestionUnknown(in: coordinator)
        let importable = try XCTUnwrap(
            coordinator.results?.items.first { !coordinator.alreadySavedKeys.contains($0.id) }
        )
        for item in coordinator.results?.items ?? [] {
            coordinator.updateSelection(item.id, selected: false)
        }
        coordinator.updateSelection(importable.id, selected: true)
        coordinator.updateSelection("read", selected: true)
        XCTAssertFalse(coordinator.selectedKeys.contains("read"))

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
            definitionProvider: FakeVocabularyPreparationDefinitionProvider()
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
