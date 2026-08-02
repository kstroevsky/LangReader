import Foundation

/// An open measurement. Returned by `begin` and handed back to `end`, so two
/// overlapping measurements of the same event cannot be confused for one
/// another the way a single stored start time would.
package struct PerformanceSpan: Sendable {
    package let event: PerformanceEvent
    fileprivate let startUptime: TimeInterval
}

/// Collects timing samples across a run and summarises them.
///
/// Deliberately platform-neutral: it knows nothing about signposts, AppKit, or
/// logging — the app wraps it to emit an `os_signpost` and to print the report.
/// Keeping the arithmetic here means the part that is easy to get subtly wrong
/// (medians, means, overlapping spans) is the part that has unit tests, and the
/// same recorder would drive an iOS build unchanged.
///
/// The clock is injectable so tests can feed exact durations instead of racing
/// a wall clock. In production it is the monotonic process uptime, which does
/// not jump when the system clock is adjusted.
package final class PerformanceRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let clock: @Sendable () -> TimeInterval
    private var samples: [PerformanceEvent: [Double]] = [:]

    package init(clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
    }

    /// Opens a span. Pair it with `end`. Overlapping spans are fine — each holds
    /// its own start — which matters for a surface that can be opened twice
    /// before the first finishes.
    package func begin(_ event: PerformanceEvent) -> PerformanceSpan {
        PerformanceSpan(event: event, startUptime: clock())
    }

    /// Closes a span and records its elapsed milliseconds.
    package func end(_ span: PerformanceSpan) {
        record(span.event, milliseconds: elapsedMS(since: span.startUptime))
    }

    /// Records a duration measured elsewhere — used for the launch marks, whose
    /// clock starts before this recorder exists.
    package func record(_ event: PerformanceEvent, milliseconds: Double) {
        let clamped = max(0, milliseconds)
        lock.lock()
        samples[event, default: []].append(clamped)
        lock.unlock()
    }

    /// Times `body` and records it under `event`, returning body's result. The
    /// measurement is taken even when `body` throws, so a failed open still
    /// shows up in the numbers rather than silently vanishing.
    @discardableResult
    package func measure<T>(_ event: PerformanceEvent, _ body: () throws -> T) rethrows -> T {
        let span = begin(event)
        defer { end(span) }
        return try body()
    }

    /// Every event that has at least one sample, summarised. Events never
    /// recorded are simply absent — a baseline should not claim a number it
    /// never observed.
    package func report() -> PerformanceReport {
        lock.lock()
        let snapshot = samples
        lock.unlock()
        let rows = snapshot.compactMap { event, values -> PerformanceReport.Row? in
            values.isEmpty ? nil : PerformanceReport.Row(event: event, samples: values)
        }
        return PerformanceReport(rows: rows)
    }

    /// Drops all samples. For tests and for a capture run that wants to discard
    /// warm-up before measuring.
    package func reset() {
        lock.lock()
        samples.removeAll()
        lock.unlock()
    }

    private func elapsedMS(since start: TimeInterval) -> Double {
        (clock() - start) * 1000
    }
}
