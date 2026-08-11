import Foundation

/// The summary of every sample collected in a run, one row per event that has
/// at least one sample.
///
/// This is the thing a baseline *is*: a migration is performance-gated by
/// comparing the report before a change against the report after it, so the
/// numbers have to be summarised the same way every time and serialised
/// deterministically. That is why the JSON is hand-built and sorted rather than
/// encoded from a dictionary — a diff of two baselines must reflect a real
/// change in the numbers, never a reordering.
package struct PerformanceReport: Equatable {
    package struct Row: Equatable {
        package let event: PerformanceEvent
        /// Samples in observation order. Summaries are useful for a quick diff,
        /// but the raw values are the evidence needed to recompute percentiles,
        /// uncertainty, and paired comparisons without rerunning the app.
        package let samplesMS: [Double]
        package let count: Int
        package let minMS: Double
        package let medianMS: Double
        package let meanMS: Double
        package let maxMS: Double

        package init(event: PerformanceEvent, samples: [Double]) {
            precondition(!samples.isEmpty, "a report row needs at least one sample")
            let sorted = samples.sorted()
            self.event = event
            samplesMS = samples
            self.count = sorted.count
            self.minMS = sorted.first!
            self.maxMS = sorted.last!
            self.meanMS = sorted.reduce(0, +) / Double(sorted.count)
            self.medianMS = PerformanceReport.median(ofSorted: sorted)
        }
    }

    package let rows: [Row]

    package init(rows: [Row]) {
        // Stable order: baselines are committed and diffed, so the row order can
        // never depend on which event happened to be recorded first.
        self.rows = rows.sorted { lhs, rhs in
            Self.order(of: lhs.event) < Self.order(of: rhs.event)
        }
    }

    /// A fixed-width table for the console and the human-readable baseline.
    package func textTable() -> String {
        guard !rows.isEmpty else { return "(no samples)" }
        let header = ["surface", "n", "min", "median", "mean", "max"]
        var widths = header.map(\.count)
        let cells: [[String]] = rows.map { row in
            [row.event.label,
             String(row.count),
             Self.ms(row.minMS),
             Self.ms(row.medianMS),
             Self.ms(row.meanMS),
             Self.ms(row.maxMS)]
        }
        for row in cells {
            for (index, value) in row.enumerated() {
                widths[index] = max(widths[index], value.count)
            }
        }
        func line(_ values: [String]) -> String {
            values.enumerated()
                .map { index, value in
                    index == 0
                        ? value.padding(toLength: widths[index], withPad: " ", startingAt: 0)
                        : String(repeating: " ", count: widths[index] - value.count) + value
                }
                .joined(separator: "  ")
        }
        return ([line(header)] + cells.map(line)).joined(separator: "\n")
    }

    /// Deterministic JSON for the committed baseline. Numbers are rounded to one
    /// decimal so an insignificant sub-millisecond wobble is not a diff.
    package func json(metadata: [String: String] = [:]) -> String {
        let events = rows.map { row -> String in
            let samples = row.samplesMS
                .map(Self.rounded)
                .joined(separator: ", ")
            return """
              {
                "event": "\(row.event.rawValue)",
                "label": "\(row.event.label)",
                "count": \(row.count),
                "min_ms": \(Self.rounded(row.minMS)),
                "median_ms": \(Self.rounded(row.medianMS)),
                "mean_ms": \(Self.rounded(row.meanMS)),
                "max_ms": \(Self.rounded(row.maxMS)),
                "samples_ms": [\(samples)]
              }
            """
        }
        let metadataRows = metadata.keys.sorted().map { key in
            "    \"\(Self.jsonEscaped(key))\": \"\(Self.jsonEscaped(metadata[key] ?? ""))\""
        }
        let metadataJSON = metadataRows.isEmpty
            ? "{}"
            : "{\n" + metadataRows.joined(separator: ",\n") + "\n  }"
        return "{\n  \"schema_version\": 2,\n  \"metadata\": \(metadataJSON),\n  \"events\": [\n"
            + events.joined(separator: ",\n") + "\n  ]\n}\n"
    }

    private static func median(ofSorted sorted: [Double]) -> Double {
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func ms(_ value: Double) -> String {
        "\(rounded(value))ms"
    }

    private static func rounded(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func jsonEscaped(_ value: String) -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22: result += "\\\""
            case 0x5C: result += "\\\\"
            case 0x08: result += "\\b"
            case 0x0C: result += "\\f"
            case 0x0A: result += "\\n"
            case 0x0D: result += "\\r"
            case 0x09: result += "\\t"
            case 0x00...0x1F:
                result += String(format: "\\u%04X", scalar.value)
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private static func order(of event: PerformanceEvent) -> Int {
        PerformanceEvent.allCases.firstIndex(of: event) ?? .max
    }
}
