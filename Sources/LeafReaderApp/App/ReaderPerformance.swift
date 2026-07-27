import Foundation
import LeafReaderCore
import os

/// One open measurement on the app side: the core span plus the matching
/// `os_signpost` interval, so Instruments and the committed baseline stay in
/// step. Opaque on purpose — call sites hold it and hand it back, nothing else.
struct ReaderPerformanceSpan {
    fileprivate let core: PerformanceSpan?
    fileprivate let signpostState: OSSignpostIntervalState?
    fileprivate let event: PerformanceEvent?

    fileprivate static let inactive = ReaderPerformanceSpan(core: nil, signpostState: nil, event: nil)
}

/// The app's window onto the core `PerformanceRecorder`: it adds signpost
/// emission, the on/off switch, and writing the baseline out.
///
/// Everything is a no-op unless `LEAFVOCAB_PERF=1`. That is what lets the
/// `begin`/`end` calls sit directly on hot paths like `loadPDF` and
/// `applyReaderTheme` without a guard at every call site and without costing a
/// normal launch anything measurable — a disabled `begin` is two comparisons
/// and a struct return.
enum ReaderPerformance {
    /// Captured once. A capture run sets it; a shipped launch never does.
    static let isEnabled: Bool =
        ProcessInfo.processInfo.environment["LEAFVOCAB_PERF"] == "1"

    static let recorder = PerformanceRecorder()

    private static let signposter = OSSignposter(
        subsystem: "com.leafvocabulary.app",
        category: "performance"
    )

    /// Opens a measurement. Returns an inactive span when disabled, so `end`
    /// has nothing to do.
    static func begin(_ event: PerformanceEvent) -> ReaderPerformanceSpan {
        guard isEnabled else { return .inactive }
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval(
            "surface",
            id: signpostID,
            "\(event.rawValue, privacy: .public)"
        )
        return ReaderPerformanceSpan(
            core: recorder.begin(event),
            signpostState: state,
            event: event
        )
    }

    /// Closes a measurement opened by `begin`.
    static func end(_ span: ReaderPerformanceSpan) {
        guard isEnabled, let core = span.core else { return }
        recorder.end(core)
        if let state = span.signpostState {
            signposter.endInterval("surface", state)
        }
    }

    /// Times `body` under `event`. Zero overhead when disabled beyond the call.
    @discardableResult
    static func measure<T>(_ event: PerformanceEvent, _ body: () -> T) -> T {
        guard isEnabled else { return body() }
        let span = begin(event)
        defer { end(span) }
        return body()
    }

    /// Records a duration measured elsewhere — the launch marks, whose clock
    /// predates this recorder.
    static func record(_ event: PerformanceEvent, milliseconds: Double) {
        guard isEnabled else { return }
        recorder.record(event, milliseconds: milliseconds)
    }

    /// Folds the launch tracker's marks into the recorder so the baseline has
    /// one report, not two. Idempotent enough for a single end-of-run call.
    static func absorbLaunchMarks(_ snapshot: LaunchPerformanceSnapshot?) {
        guard isEnabled, let snapshot else { return }
        recorder.record(.launch, milliseconds: Double(snapshot.totalMilliseconds))
        if let windowMark = snapshot.marks.first(where: { $0.name == "windowVisible" }) {
            recorder.record(.mainWindow, milliseconds: Double(windowMark.milliseconds))
        }
    }

    /// The human-readable table, for logging at the end of a capture run.
    static func reportText() -> String {
        recorder.report().textTable()
    }

    /// Writes the baseline where a capture run can pick it up: JSON next to a
    /// human table. Destination comes from `LEAFVOCAB_PERF_OUT`; when unset it
    /// only logs, so an accidental enabled launch does not litter the disk.
    static func writeBaselineIfRequested(launch: LaunchPerformanceSnapshot?) {
        guard isEnabled else { return }
        absorbLaunchMarks(launch)
        let report = recorder.report()
        os_log("%{public}@", log: .default, type: .info,
               "LeafReader performance baseline:\n" + report.textTable())

        guard let outPath = ProcessInfo.processInfo.environment["LEAFVOCAB_PERF_OUT"],
              !outPath.isEmpty else { return }
        let base = URL(fileURLWithPath: outPath)
        try? report.json().write(to: base.appendingPathExtension("json"),
                                 atomically: true, encoding: .utf8)
        try? report.textTable().write(to: base.appendingPathExtension("txt"),
                                      atomically: true, encoding: .utf8)
    }
}
