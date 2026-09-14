import Foundation
import LeafReaderCore

@MainActor
struct VocabularyPreparationInteractionTiming {
    private let isEnabled: @MainActor () -> Bool
    private let clock: () -> TimeInterval
    private let sink: @MainActor (VocabularyPreparationInteractionTimingObservation) -> Void
    private var starts: [VocabularyPreparationInteractionTimingKind: TimeInterval] = [:]

    init(
        isEnabled: @escaping @MainActor () -> Bool,
        clock: @escaping () -> TimeInterval,
        sink: @escaping @MainActor (VocabularyPreparationInteractionTimingObservation) -> Void
    ) {
        self.isEnabled = isEnabled
        self.clock = clock
        self.sink = sink
    }

    static var live: Self {
        Self(
            isEnabled: { ReaderPerformance.isEnabled },
            clock: { ProcessInfo.processInfo.systemUptime },
            sink: { ReaderPerformance.recordVocabularyInteraction($0) }
        )
    }

    mutating func answerTapped() { start(.answerToLearningContentVisible) }
    mutating func learningContentVisible() { finish(.answerToLearningContentVisible, outcome: .completed) }
    mutating func learningContentFailed() { finish(.answerToLearningContentVisible, outcome: .failed) }
    mutating func continueTapped() {
        start(.continueToNextWordVisible)
        start(.continueToNextWordAnswerable)
    }
    mutating func knownVerificationTapped() { start(.knownVerificationToNextWordAnswerable) }
    mutating func nextWordVisible() { finish(.continueToNextWordVisible, outcome: .completed) }
    mutating func nextWordAnswerable() {
        finish(.continueToNextWordAnswerable, outcome: .completed)
        finish(.knownVerificationToNextWordAnswerable, outcome: .completed)
    }
    mutating func terminalResult() { finishAll(outcome: .terminal) }
    mutating func cancel() { finishAll(outcome: .cancelled) }

    private mutating func start(_ kind: VocabularyPreparationInteractionTimingKind) {
        guard isEnabled(), starts[kind] == nil else { return }
        starts[kind] = clock()
    }

    private mutating func finish(
        _ kind: VocabularyPreparationInteractionTimingKind,
        outcome: VocabularyPreparationInteractionTimingOutcome
    ) {
        guard let startedAt = starts.removeValue(forKey: kind) else { return }
        sink(VocabularyPreparationInteractionTimingObservation(
            kind: kind,
            outcome: outcome,
            milliseconds: outcome == .completed ? max(0, clock() - startedAt) * 1_000 : nil
        ))
    }

    private mutating func finishAll(outcome: VocabularyPreparationInteractionTimingOutcome) {
        for kind in starts.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            finish(kind, outcome: outcome)
        }
    }
}
