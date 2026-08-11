#!/usr/bin/env swift
import Foundation

private struct Report: Decodable {
    struct Event: Decodable {
        let event: String
        let medianMS: Double

        enum CodingKeys: String, CodingKey {
            case event
            case medianMS = "median_ms"
        }
    }

    let metadata: [String: String]
    let events: [Event]
}

private enum SummaryError: LocalizedError {
    case usage
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "usage: summarize_docx_performance.swift [--accept-primary] <pair-1.cold.json> <pair-1.warm.json> [...]"
        case .invalid(let message):
            return message
        }
    }
}

private func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2)
        ? (sorted[middle - 1] + sorted[middle]) / 2
        : sorted[middle]
}

do {
    var arguments = Array(CommandLine.arguments.dropFirst())
    let enforceAcceptance = arguments.first == "--accept-primary"
    if enforceAcceptance { arguments.removeFirst() }
    guard !arguments.isEmpty, arguments.count.isMultiple(of: 2) else { throw SummaryError.usage }

    var coldPreparation: [Double] = []
    var coldVisible: [Double] = []
    var warmPreparation: [Double] = []
    var warmVisible: [Double] = []
    var expectedBuild: String?

    func measurements(path: String, expectedPhase: String) throws -> (Double, Double) {
        let report = try JSONDecoder().decode(
            Report.self,
            from: Data(contentsOf: URL(fileURLWithPath: path))
        )
        guard report.metadata["phase"] == expectedPhase else {
            throw SummaryError.invalid("\(path) is not a \(expectedPhase) capture")
        }
        let build = report.metadata["build_sha256"] ?? ""
        if let expectedBuild, build != expectedBuild {
            throw SummaryError.invalid("captures do not use one immutable Release binary")
        }
        expectedBuild = build
        let rows = Dictionary(uniqueKeysWithValues: report.events.map { ($0.event, $0.medianMS) })
        guard let prep = rows["docxPreparation"], let ready = rows["docxVisibleReady"] else {
            throw SummaryError.invalid("\(path) has no DOCX preparation/visible-ready measurements")
        }
        return (prep, ready)
    }

    for index in stride(from: 0, to: arguments.count, by: 2) {
        let cold = try measurements(path: arguments[index], expectedPhase: "cold")
        coldPreparation.append(cold.0)
        coldVisible.append(cold.1)
        let warm = try measurements(path: arguments[index + 1], expectedPhase: "warm")
        warmPreparation.append(warm.0)
        warmVisible.append(warm.1)
    }

    let coldPrepMedian = median(coldPreparation)
    let coldVisibleMedian = median(coldVisible)
    let warmPrepMedian = median(warmPreparation)
    let warmVisibleMedian = median(warmVisible)
    print("DOCX pairs: \(coldPreparation.count)")
    print(String(format: "Cold preparation median: %.1f ms", coldPrepMedian))
    print(String(format: "Cold visible-ready median: %.1f ms", coldVisibleMedian))
    print(String(format: "Warm preparation median: %.1f ms", warmPrepMedian))
    print(String(format: "Warm visible-ready median: %.1f ms", warmVisibleMedian))

    if enforceAcceptance {
        guard coldPreparation.count >= 5 else {
            throw SummaryError.invalid("primary acceptance requires at least five isolated pairs")
        }
        let baseline = (coldPrep: 1_745.4, coldVisible: 2_028.3, warmPrep: 1_750.7, warmVisible: 1_950.2)
        let coldPrepImprovement = 1 - coldPrepMedian / baseline.coldPrep
        let coldVisibleImprovement = 1 - coldVisibleMedian / baseline.coldVisible
        let warmPrepImprovement = 1 - warmPrepMedian / baseline.warmPrep
        let warmVisibleImprovement = 1 - warmVisibleMedian / baseline.warmVisible
        print(String(format: "Cold preparation improvement: %.1f%%", coldPrepImprovement * 100))
        print(String(format: "Cold visible-ready improvement: %.1f%%", coldVisibleImprovement * 100))
        print(String(format: "Warm preparation improvement: %.1f%%", warmPrepImprovement * 100))
        print(String(format: "Warm visible-ready improvement: %.1f%%", warmVisibleImprovement * 100))
        guard coldPrepImprovement >= 0.50,
              coldVisibleImprovement >= 0.50,
              warmPrepImprovement >= 0.70,
              warmVisibleImprovement >= 0.70,
              coldVisibleMedian <= 1_000,
              warmVisibleMedian <= 500 else {
            throw SummaryError.invalid("primary DOCX timing acceptance failed")
        }
        print("Primary DOCX timing acceptance: PASS")
    }
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
