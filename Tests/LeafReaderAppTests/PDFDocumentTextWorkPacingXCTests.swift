import XCTest
import LeafReaderCore
@testable import LeafReaderApp

final class PDFDocumentTextWorkPacingXCTests: XCTestCase {
    func testVocabularyIndexBuildIsCancelledWhenSemanticIdentityChanges() {
        var state = ReaderDocumentTextState()
        let english = VocabularyLinguisticCacheIdentity(language: .english)
        let german = VocabularyLinguisticCacheIdentity(language: .german)
        let token = PDFDocumentTextCancellationToken()
        state.isBuildingVocabularyIndex = true
        state.vocabularyIndexBuildSemanticIdentity = english
        state.vocabularyIndexCancellationToken = token
        state.pendingVocabularyIndexCallbacks = [{ _, _ in }]

        let staleCallbacks = state.cancelVocabularyIndexBuildIfSemanticsChanged(to: german)

        XCTAssertTrue(token.isCancelled)
        XCTAssertEqual(staleCallbacks.count, 1)
        XCTAssertFalse(state.isBuildingVocabularyIndex)
        XCTAssertNil(state.vocabularyIndexBuildSemanticIdentity)
        XCTAssertNil(state.vocabularyIndexCancellationToken)
        XCTAssertTrue(state.pendingVocabularyIndexCallbacks.isEmpty)
    }

    func testVocabularyIndexBuildCoalescesMatchingSemanticIdentity() {
        var state = ReaderDocumentTextState()
        let english = VocabularyLinguisticCacheIdentity(language: .english)
        let token = PDFDocumentTextCancellationToken()
        state.isBuildingVocabularyIndex = true
        state.vocabularyIndexBuildSemanticIdentity = english
        state.vocabularyIndexCancellationToken = token

        let staleCallbacks = state.cancelVocabularyIndexBuildIfSemanticsChanged(to: english)

        XCTAssertTrue(staleCallbacks.isEmpty)
        XCTAssertFalse(token.isCancelled)
        XCTAssertTrue(state.isBuildingVocabularyIndex)
        XCTAssertEqual(state.vocabularyIndexBuildSemanticIdentity, english)
        XCTAssertTrue(state.vocabularyIndexCancellationToken === token)
    }

    func testDeferredBackgroundWorkYieldsAndThenResumes() {
        let token = PDFDocumentTextCancellationToken()
        token.deferWork(for: 0.03)
        let startedAt = ProcessInfo.processInfo.systemUptime

        XCTAssertFalse(token.waitUntilRunnableOrCancelled())
        XCTAssertGreaterThanOrEqual(
            ProcessInfo.processInfo.systemUptime - startedAt,
            0.02
        )
    }

    func testCancellationWinsOverDeferral() {
        let token = PDFDocumentTextCancellationToken()
        token.deferWork(for: 1)
        token.cancel()
        let startedAt = ProcessInfo.processInfo.systemUptime

        XCTAssertTrue(token.waitUntilRunnableOrCancelled())
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - startedAt, 0.05)
    }
}
