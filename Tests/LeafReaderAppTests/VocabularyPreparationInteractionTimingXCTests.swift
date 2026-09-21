import XCTest
@testable import LeafReaderApp

@MainActor
final class VocabularyPreparationInteractionTimingXCTests: XCTestCase {
    func testCompletedSpansUseOneMonotonicStartPerInteraction() {
        var now = 1.0
        var observations: [VocabularyPreparationInteractionTimingObservation] = []
        var timing = VocabularyPreparationInteractionTiming(
            isEnabled: { true },
            clock: { now },
            sink: { observations.append($0) }
        )

        timing.answerTapped()
        now = 1.012
        timing.learningContentVisible()
        timing.continueTapped()
        timing.continueTapped()
        now = 1.020
        timing.nextWordVisible()
        now = 1.025
        timing.nextWordAnswerable()
        timing.knownVerificationTapped()
        now = 1.034
        timing.nextWordAnswerable()

        XCTAssertEqual(observations.map(\.kind), [
            .answerToLearningContentVisible,
            .continueToNextWordVisible,
            .continueToNextWordAnswerable,
            .knownVerificationToNextWordAnswerable
        ])
        XCTAssertEqual(observations.map(\.outcome), Array(repeating: .completed, count: 4))
        XCTAssertEqual(observations[0].milliseconds ?? -1, 12, accuracy: 0.000_001)
        XCTAssertEqual(observations[1].milliseconds ?? -1, 8, accuracy: 0.000_001)
        XCTAssertEqual(observations[2].milliseconds ?? -1, 13, accuracy: 0.000_001)
        XCTAssertEqual(observations[3].milliseconds ?? -1, 9, accuracy: 0.000_001)
    }

    func testFailedTerminalCancelledAndDisabledPathsDoNotInventDurations() {
        var observations: [VocabularyPreparationInteractionTimingObservation] = []
        var timing = VocabularyPreparationInteractionTiming(
            isEnabled: { true },
            clock: { 10 },
            sink: { observations.append($0) }
        )
        timing.answerTapped()
        timing.learningContentFailed()
        timing.continueTapped()
        timing.terminalResult()
        timing.knownVerificationTapped()
        timing.cancel()

        XCTAssertEqual(observations.map(\.outcome), [.failed, .terminal, .terminal, .cancelled])
        XCTAssertTrue(observations.allSatisfy { $0.milliseconds == nil })

        var disabled = VocabularyPreparationInteractionTiming(
            isEnabled: { false },
            clock: { XCTFail("disabled timing read the clock"); return 0 },
            sink: { _ in XCTFail("disabled timing emitted") }
        )
        disabled.answerTapped()
        disabled.continueTapped()
        disabled.knownVerificationTapped()
        disabled.cancel()
    }
}
