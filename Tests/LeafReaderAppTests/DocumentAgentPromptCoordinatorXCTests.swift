import XCTest
@testable import LeafReaderApp

@MainActor
final class DocumentAgentPromptCoordinatorXCTests: XCTestCase {
    func testCallbackRequestsCompleteIndependently() {
        let coordinator = DocumentAgentPromptCoordinator()
        var finishes: [UUID: DocumentAgentPromptCoordinator.Finish] = [:]
        var results: [String?] = []

        let firstID = coordinator.request(
            starting: { requestID, finish in finishes[requestID] = finish },
            completion: { results.append($0) }
        )
        let secondID = coordinator.request(
            starting: { requestID, finish in finishes[requestID] = finish },
            completion: { results.append($0) }
        )

        XCTAssertEqual(coordinator.activeRequestCount, 2)
        finishes[secondID]?("second")
        XCTAssertEqual(results, ["second"])
        XCTAssertTrue(coordinator.isActive(firstID))
        XCTAssertFalse(coordinator.isActive(secondID))

        finishes[firstID]?("first")
        XCTAssertEqual(results, ["second", "first"])
        XCTAssertEqual(coordinator.activeRequestCount, 0)
    }

    func testAsyncRequestResumesWithItsResult() async {
        let coordinator = DocumentAgentPromptCoordinator()

        let result = await coordinator.request { _, finish in
            finish("answer")
        }

        XCTAssertEqual(result, "answer")
        XCTAssertEqual(coordinator.activeRequestCount, 0)
    }

    func testCancellationCancelsOnlyMatchingRequestAndAuxiliaryTask() async {
        let coordinator = DocumentAgentPromptCoordinator()
        var firstFinish: DocumentAgentPromptCoordinator.Finish?
        var secondFinish: DocumentAgentPromptCoordinator.Finish?

        let firstID = coordinator.request(
            starting: { _, finish in firstFinish = finish },
            completion: { _ in }
        )
        let secondID = coordinator.request(
            starting: { _, finish in secondFinish = finish },
            completion: { _ in }
        )
        let auxiliaryTask = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(60))
        }
        coordinator.replaceAuxiliaryTask(auxiliaryTask, for: firstID)

        coordinator.cancel(firstID)

        XCTAssertTrue(auxiliaryTask.isCancelled)
        XCTAssertFalse(coordinator.isActive(firstID))
        XCTAssertTrue(coordinator.isActive(secondID))
        firstFinish?("late result")
        XCTAssertTrue(coordinator.isActive(secondID))
        secondFinish?("still active")
        XCTAssertEqual(coordinator.activeRequestCount, 0)
    }
}
