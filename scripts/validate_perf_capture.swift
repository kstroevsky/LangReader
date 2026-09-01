import Foundation

struct Report: Decodable {
    struct Event: Decodable {
        let event: String
        let count: Int
        let minMS: Double
        let medianMS: Double
        let meanMS: Double
        let maxMS: Double
        let samplesMS: [Double]

        enum CodingKeys: String, CodingKey {
            case event, count
            case minMS = "min_ms"
            case medianMS = "median_ms"
            case meanMS = "mean_ms"
            case maxMS = "max_ms"
            case samplesMS = "samples_ms"
        }
    }
    let schemaVersion: Int
    let metadata: [String: String]
    let events: [Event]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case metadata, events
    }
}

enum ValidationError: LocalizedError {
    case usage
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "usage: validate_perf_capture.swift <synthetic|documents|docx|matrix|interactions|vocabulary-preparation|private> <report.json> [--not-before unix-seconds] [--expected-phase phase] [--control report.json]"
        case .invalid(let message):
            return "Invalid performance capture: \(message)"
        }
    }
}

func require(_ counts: [String: Int], _ event: String, atLeast expected: Int) throws {
    let actual = counts[event] ?? 0
    guard actual >= expected else {
        throw ValidationError.invalid("\(event) needs \(expected) samples, found \(actual)")
    }
}

func forbid(_ counts: [String: Int], _ event: String) throws {
    guard (counts[event] ?? 0) == 0 else {
        throw ValidationError.invalid("\(event) must not be present in this capture phase")
    }
}

func approximatelyEqual(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.11) -> Bool {
    abs(lhs - rhs) <= tolerance
}

func median(_ sorted: [Double]) -> Double {
    let middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2)
        ? (sorted[middle - 1] + sorted[middle]) / 2
        : sorted[middle]
}

func percentile(_ sorted: [Double], _ quantile: Double) -> Double {
    guard sorted.count > 1 else { return sorted[0] }
    let position = min(max(quantile, 0), 1) * Double(sorted.count - 1)
    let lower = Int(position.rounded(.down))
    let upper = Int(position.rounded(.up))
    guard lower != upper else { return sorted[lower] }
    let fraction = position - Double(lower)
    return sorted[lower] + ((sorted[upper] - sorted[lower]) * fraction)
}

func validateRawSamples(_ row: Report.Event) throws {
    guard row.count == row.samplesMS.count else {
        throw ValidationError.invalid("\(row.event) count \(row.count) does not match \(row.samplesMS.count) raw samples")
    }
    guard !row.samplesMS.isEmpty,
          row.samplesMS.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
        throw ValidationError.invalid("\(row.event) has missing, negative, or non-finite raw samples")
    }
    let sorted = row.samplesMS.sorted()
    let expectedMean = sorted.reduce(0, +) / Double(sorted.count)
    for (name, actual, expected) in [
        ("min_ms", row.minMS, sorted.first!),
        ("median_ms", row.medianMS, median(sorted)),
        ("mean_ms", row.meanMS, expectedMean),
        ("max_ms", row.maxMS, sorted.last!)
    ] where !approximatelyEqual(actual, expected) {
        throw ValidationError.invalid("\(row.event) \(name) does not match its raw samples")
    }
}

func requireMaximum(_ rows: [String: Report.Event], _ event: String, atMost threshold: Double) throws {
    guard let row = rows[event] else {
        throw ValidationError.invalid("\(event) is required for threshold validation")
    }
    guard row.maxMS <= threshold else {
        throw ValidationError.invalid("\(event) max \(row.maxMS)ms exceeds \(threshold)ms")
    }
}

func requireMedian(_ rows: [String: Report.Event], _ event: String, atMost threshold: Double) throws {
    guard let row = rows[event] else {
        throw ValidationError.invalid("\(event) is required for threshold validation")
    }
    guard row.medianMS <= threshold else {
        throw ValidationError.invalid("\(event) median \(row.medianMS)ms exceeds \(threshold)ms")
    }
}

func requirePercentile(
    _ rows: [String: Report.Event],
    _ event: String,
    quantile: Double,
    atMost threshold: Double
) throws {
    guard let row = rows[event] else {
        throw ValidationError.invalid("\(event) is required for threshold validation")
    }
    let actual = percentile(row.samplesMS.sorted(), quantile)
    guard actual <= threshold else {
        throw ValidationError.invalid(
            "\(event) p\(Int(quantile * 100)) \(actual)ms exceeds \(threshold)ms"
        )
    }
}

do {
    guard CommandLine.arguments.count >= 3,
          let mode = ["synthetic", "documents", "docx", "matrix", "interactions", "vocabulary-preparation", "private"].first(where: { $0 == CommandLine.arguments[1] }) else {
        throw ValidationError.usage
    }
    let url = URL(fileURLWithPath: CommandLine.arguments[2])
    var notBefore: TimeInterval?
    var expectedPhase: String?
    var controlURL: URL?
    var argumentIndex = 3
    while argumentIndex < CommandLine.arguments.count {
        guard argumentIndex + 1 < CommandLine.arguments.count else { throw ValidationError.usage }
        switch CommandLine.arguments[argumentIndex] {
        case "--not-before":
            guard let value = TimeInterval(CommandLine.arguments[argumentIndex + 1]) else { throw ValidationError.usage }
            notBefore = value
        case "--expected-phase":
            expectedPhase = CommandLine.arguments[argumentIndex + 1]
        case "--control":
            controlURL = URL(fileURLWithPath: CommandLine.arguments[argumentIndex + 1])
        default:
            throw ValidationError.usage
        }
        argumentIndex += 2
    }
    if let threshold = notBefore {
        let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
        guard modified.timeIntervalSince1970 >= threshold else {
            throw ValidationError.invalid("report predates this capture run")
        }
    }
    let data = try Data(contentsOf: url)
    let report = try JSONDecoder().decode(Report.self, from: data)
    guard report.schemaVersion == 2 else {
        throw ValidationError.invalid("schema_version must be 2 so raw samples are available")
    }
    guard let phase = report.metadata["phase"], !phase.isEmpty, phase != "unclassified" else {
        throw ValidationError.invalid("metadata.phase must classify the capture")
    }
    if let expectedPhase, phase != expectedPhase {
        throw ValidationError.invalid("metadata.phase is \(phase), expected \(expectedPhase)")
    }
    for requiredMetadata in ["configuration", "source_revision", "build_sha256", "fixture_set", "run_id"] {
        guard let value = report.metadata[requiredMetadata], !value.isEmpty else {
            throw ValidationError.invalid("metadata.\(requiredMetadata) is required")
        }
    }
    guard !report.events.isEmpty else {
        throw ValidationError.invalid("report has no events")
    }
    var counts: [String: Int] = [:]
    var rows: [String: Report.Event] = [:]
    for row in report.events {
        try validateRawSamples(row)
        guard rows[row.event] == nil else { throw ValidationError.invalid("duplicate \(row.event) row") }
        counts[row.event, default: 0] += row.count
        rows[row.event] = row
    }
    try require(counts, "launch", atLeast: 1)
    try require(counts, "mainWindow", atLeast: 1)
    switch mode {
    case "synthetic":
        try require(counts, "pdfOpen", atLeast: 2)
        try require(counts, "firstPageDisplay", atLeast: 2)
        try require(counts, "documentVisibleReady", atLeast: 2)
        try require(counts, "pdfVisibleReady", atLeast: 2)
    case "documents", "docx":
        try require(counts, "pdfOpen", atLeast: 1)
        try require(counts, "webDocumentPreparation", atLeast: 2)
        try require(counts, "epubPreparation", atLeast: 1)
        try require(counts, "docxPreparation", atLeast: 1)
        try require(counts, "webOpen", atLeast: 2)
        try require(counts, "webContentReady", atLeast: 2)
        try require(counts, "epubContentReady", atLeast: 1)
        try require(counts, "docxContentReady", atLeast: 1)
        try require(counts, "documentVisibleReady", atLeast: 3)
        try require(counts, "pdfVisibleReady", atLeast: 1)
        try require(counts, "epubVisibleReady", atLeast: 1)
        try require(counts, "docxVisibleReady", atLeast: 1)
        if mode == "docx" {
            try require(counts, "docxFingerprint", atLeast: 1)
            try require(counts, "docxCacheLookup", atLeast: 1)
            if phase == "cold" {
                try require(counts, "docxArchiveExtraction", atLeast: 1)
                try require(counts, "docxRelationshipParse", atLeast: 1)
                try require(counts, "docxXMLRender", atLeast: 1)
                try require(counts, "docxCacheCommit", atLeast: 1)
                try forbid(counts, "docxCacheHitLoad")
            } else if phase == "warm" {
                try require(counts, "docxCacheHitLoad", atLeast: 1)
                try forbid(counts, "docxArchiveExtraction")
                try forbid(counts, "docxRelationshipParse")
                try forbid(counts, "docxXMLRender")
                try forbid(counts, "docxCacheCommit")
            } else {
                throw ValidationError.invalid("DOCX capture phase must be cold or warm")
            }
        }
    case "matrix":
        try require(counts, "pdfOpen", atLeast: 3)
        try require(counts, "webDocumentPreparation", atLeast: 2)
        try require(counts, "epubPreparation", atLeast: 2)
        try require(counts, "webOpen", atLeast: 2)
        try require(counts, "webContentReady", atLeast: 2)
        try require(counts, "epubContentReady", atLeast: 2)
        try require(counts, "documentVisibleReady", atLeast: 5)
        try require(counts, "pdfVisibleReady", atLeast: 3)
        try require(counts, "epubVisibleReady", atLeast: 2)
    case "interactions":
        for event in [
            "searchAcknowledgement", "searchFirstVisibleResult", "searchCancellationResponse",
            "searchResultNavigation", "vocabularySaveAcknowledgement",
            "vocabularyOccurrenceQuery", "visibleHighlightMaterialization",
            "pdfZoomHighlightUpdate", "webFontHighlightUpdate", "mainThreadUninterruptedWork",
            "idleScrollFrame", "backgroundIndexScrollFrame"
        ] {
            try require(counts, event, atLeast: 1)
        }
        try requireMaximum(rows, "searchAcknowledgement", atMost: 16)
        try requireMaximum(rows, "searchFirstVisibleResult", atMost: 50)
        try requireMaximum(rows, "searchCancellationResponse", atMost: 50)
        try requireMaximum(rows, "vocabularySaveAcknowledgement", atMost: 50)
        try requireMedian(rows, "vocabularyOccurrenceQuery", atMost: 10)
        try requireMaximum(rows, "visibleHighlightMaterialization", atMost: 100)
        try requirePercentile(rows, "mainThreadUninterruptedWork", quantile: 0.95, atMost: 16)
        let idleP95 = percentile(rows["idleScrollFrame"]!.samplesMS.sorted(), 0.95)
        let backgroundP95 = percentile(rows["backgroundIndexScrollFrame"]!.samplesMS.sorted(), 0.95)
        guard backgroundP95 <= idleP95 + 8 else {
            throw ValidationError.invalid(
                "background indexing adds \(backgroundP95 - idleP95)ms to p95 paging delay (limit 8ms)"
            )
        }
    case "vocabulary-preparation":
        try require(counts, "pdfVisibleReady", atLeast: 2)
        try require(counts, "epubVisibleReady", atLeast: 2)
        try require(counts, "docxVisibleReady", atLeast: 2)
        try require(counts, "documentVisibleReady", atLeast: 6)
        try require(counts, "vocabularyPreparationInventoryBuild", atLeast: 6)
        try require(counts, "vocabularyAssessmentAdvance", atLeast: 120)
        try require(counts, "vocabularyPreparationResults", atLeast: 6)
        try require(counts, "vocabularyPreparationImport", atLeast: 6)
        try require(counts, "mainThreadUninterruptedWork", atLeast: 6)
        try requirePercentile(rows, "mainThreadUninterruptedWork", quantile: 0.95, atMost: 16)
        guard let controlURL else {
            throw ValidationError.invalid("vocabulary-preparation mode requires --control")
        }
        let control = try JSONDecoder().decode(Report.self, from: Data(contentsOf: controlURL))
        let controlRows = Dictionary(uniqueKeysWithValues: control.events.map { ($0.event, $0) })
        for event in ["documentVisibleReady", "pdfVisibleReady", "epubVisibleReady", "docxVisibleReady"] {
            guard let current = rows[event], let baseline = controlRows[event] else {
                throw ValidationError.invalid("both preparation and control reports need \(event)")
            }
            let allowance = max(baseline.medianMS * 0.10, 50)
            guard current.medianMS <= baseline.medianMS + allowance else {
                throw ValidationError.invalid(
                    "\(event) median \(current.medianMS)ms exceeds control \(baseline.medianMS)ms + \(allowance)ms"
                )
            }
        }
    case "private":
        try require(counts, "pdfOpen", atLeast: 1)
        try require(counts, "webOpen", atLeast: 2)
        try require(counts, "webContentReady", atLeast: 2)
        try require(counts, "documentVisibleReady", atLeast: 3)
        try require(counts, "pdfVisibleReady", atLeast: 1)
        try require(counts, "epubVisibleReady", atLeast: 1)
        try require(counts, "docxVisibleReady", atLeast: 1)
        for event in ["shelfOpen", "notesOpen", "vocabularyLibraryOpen", "aiPanelExpand", "selectionToolbar", "aiFirstToken", "aiStreaming", "themeSwitch"] {
            try require(counts, event, atLeast: 1)
        }
    default:
        fatalError("validated above")
    }
    print("Validated \(mode) performance capture: \(url.path)")
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
