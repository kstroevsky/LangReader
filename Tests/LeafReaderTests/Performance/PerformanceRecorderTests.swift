import Foundation
import LeafReaderCore

/// The performance recorder's arithmetic and its deterministic report — the
/// parts a baseline depends on being reproducible.
enum PerformanceRecorderTests {
    /// The harness has no `XCTUnwrap`; this is the local equivalent.
    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw TestFailure(description: message) }
        return value
    }

    /// Span-derived durations subtract two `TimeInterval`s expressed in seconds,
    /// so a value like 20ms carries sub-millisecond binary noise (0.03 − 0.01).
    /// The report keeps that full precision and only rounds when it serialises,
    /// so a span assertion must allow the same tolerance the baseline does.
    private static func expectClose(_ lhs: Double, _ rhs: Double, _ message: String) throws {
        if abs(lhs - rhs) > 0.05 {
            throw TestFailure(description: "\(message). expected ~\(rhs), got \(lhs)")
        }
    }

    /// A clock the test advances by hand, so durations are exact instead of
    /// racing a real wall clock.
    private final class FakeClock: @unchecked Sendable {
        private let lock = NSLock()
        private var seconds: TimeInterval = 0
        func advance(byMS ms: Double) {
            lock.lock(); seconds += ms / 1000; lock.unlock()
        }
        func now() -> TimeInterval {
            lock.lock(); defer { lock.unlock() }; return seconds
        }
    }

    static func testSpanRecordsElapsedMilliseconds() throws {
        let clock = FakeClock()
        let recorder = PerformanceRecorder(clock: { clock.now() })
        let span = recorder.begin(.pdfOpen)
        clock.advance(byMS: 42)
        recorder.end(span)
        let rows = recorder.report().rows
        try expectEqual(rows.count, 1, "one event recorded")
        try expectEqual(rows[0].event, .pdfOpen, "the recorded event is the one measured")
        try expectClose(rows[0].medianMS, 42, "a single span's duration is its elapsed time")
    }

    static func testStatsAcrossSamples() throws {
        let clock = FakeClock()
        let recorder = PerformanceRecorder(clock: { clock.now() })
        for ms in [10.0, 20.0, 60.0] {
            let span = recorder.begin(.themeSwitch)
            clock.advance(byMS: ms)
            recorder.end(span)
        }
        let row = try unwrap(recorder.report().rows.first, "expected at least one row")
        try expectEqual(row.count, 3, "three samples")
        for (actual, expected) in zip(row.samplesMS, [10.0, 20.0, 60.0]) {
            try expectClose(actual, expected, "raw samples retain observation order")
        }
        try expectClose(row.minMS, 10, "min is the smallest sample")
        try expectClose(row.maxMS, 60, "max is the largest sample")
        try expectClose(row.medianMS, 20, "median of 10/20/60 is the middle value")
        try expectClose(row.meanMS, 30, "mean of 10/20/60 is 30")
    }

    static func testMedianOfEvenCountAveragesMiddlePair() throws {
        let recorder = PerformanceRecorder()
        for ms in [10.0, 20.0, 30.0, 40.0] {
            recorder.record(.selectionToolbar, milliseconds: ms)
        }
        let row = try unwrap(recorder.report().rows.first, "expected at least one row")
        try expectEqual(row.medianMS, 25, "even-count median averages the two middle samples")
    }

    static func testNegativeDurationsAreClampedToZero() throws {
        // A clock that runs backwards (or a span ended before it began) must not
        // pollute the baseline with a negative duration.
        let recorder = PerformanceRecorder()
        recorder.record(.launch, milliseconds: -5)
        let row = try unwrap(recorder.report().rows.first, "expected at least one row")
        try expectEqual(row.minMS, 0, "a negative measurement is clamped to zero")
    }

    static func testUnrecordedEventsAreAbsent() throws {
        let recorder = PerformanceRecorder()
        recorder.record(.pdfOpen, milliseconds: 5)
        let events = recorder.report().rows.map(\.event)
        try expect(!events.contains(.webOpen), "an event never measured has no row")
    }

    static func testReportRowsAreInEventOrderRegardlessOfRecordOrder() throws {
        let recorder = PerformanceRecorder()
        // Record out of declaration order; the report must not reflect that.
        recorder.record(.themeSwitch, milliseconds: 1)
        recorder.record(.launch, milliseconds: 1)
        recorder.record(.pdfOpen, milliseconds: 1)
        let order = recorder.report().rows.map(\.event)
        try expectEqual(order, [.launch, .pdfOpen, .themeSwitch],
                        "rows follow PerformanceEvent declaration order, so two baselines diff cleanly")
    }

    static func testJSONIsDeterministicAndRounded() throws {
        let recorder = PerformanceRecorder()
        recorder.record(.launch, milliseconds: 250.06)
        recorder.record(.launch, milliseconds: 249.9)
        let json = recorder.report().json()
        try expect(json.contains("\"event\": \"launch\""), "JSON keys the row by the stable raw value")
        try expect(json.contains("\"count\": 2"), "JSON reports the sample count")
        try expect(json.contains("\"median_ms\": 250.0"), "JSON rounds to one decimal for stable diffs")
        try expect(json.contains("\"samples_ms\": [250.1, 249.9]"), "JSON preserves rounded raw samples in observation order")
        try expect(json.contains("\"schema_version\": 2"), "JSON declares the raw-sample schema")
    }

    static func testJSONMetadataIsDeterministicAndEscaped() throws {
        let recorder = PerformanceRecorder()
        recorder.record(.launch, milliseconds: 1)
        let json = recorder.report().json(metadata: [
            "source_revision": "abc123",
            "phase": "cold\nrun"
        ])
        let phaseRange = try unwrap(json.range(of: "\"phase\""), "phase metadata should exist")
        let revisionRange = try unwrap(json.range(of: "\"source_revision\""), "revision metadata should exist")
        try expect(phaseRange.lowerBound < revisionRange.lowerBound, "metadata keys are serialized in stable order")
        try expect(json.contains("cold\\nrun"), "metadata values are JSON escaped")
    }

    static func testResetDiscardsSamples() throws {
        let recorder = PerformanceRecorder()
        recorder.record(.pdfOpen, milliseconds: 5)
        recorder.reset()
        try expect(recorder.report().rows.isEmpty, "reset clears every sample")
    }

    static func testVocabularyPreparationPhaseEventsRemainStableAndOrdered() throws {
        let recorder = PerformanceRecorder()
        recorder.record(.vocabularyPreparationImportPersistence, milliseconds: 8)
        recorder.record(.vocabularyAssessmentPosteriorUpdate, milliseconds: 3)
        recorder.record(.vocabularyPreparationSourceSnapshot, milliseconds: 5)

        let report = recorder.report()
        try expectEqual(
            report.rows.map(\.event),
            [
                .vocabularyPreparationSourceSnapshot,
                .vocabularyAssessmentPosteriorUpdate,
                .vocabularyPreparationImportPersistence
            ],
            "preparation phase telemetry follows the stable PerformanceEvent contract"
        )
        let json = report.json()
        try expect(
            json.contains("\"event\": \"vocabularyAssessmentPosteriorUpdate\""),
            "phase telemetry is exported to the deterministic capture JSON"
        )
    }
}
