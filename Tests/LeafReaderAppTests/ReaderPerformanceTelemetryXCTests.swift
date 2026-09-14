import XCTest
@testable import LeafReaderApp

@MainActor
final class ReaderPerformanceTelemetryXCTests: XCTestCase {
    func testVocabularyMilestoneUsesStableAggregateOnlyContract() {
        XCTAssertEqual(VocabularyPreparationTelemetryStage.inventory.rawValue, "inventory")
        XCTAssertEqual(VocabularyPreparationTelemetryOutcome.completed.rawValue, "completed")

        ReaderPerformance.logVocabularyPreparation(
            .inventory,
            milliseconds: 12.5,
            itemCount: 400,
            auxiliaryCount: 8
        )
    }
}
