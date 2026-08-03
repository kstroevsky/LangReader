import Foundation

struct Report: Decodable {
    struct Event: Decodable {
        let event: String
        let count: Int
    }
    let events: [Event]
}

enum ValidationError: LocalizedError {
    case usage
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "usage: validate_perf_capture.swift <synthetic|documents|private> <report.json> [--not-before unix-seconds]"
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

do {
    guard CommandLine.arguments.count == 3 || CommandLine.arguments.count == 5,
          let mode = ["synthetic", "documents", "private"].first(where: { $0 == CommandLine.arguments[1] }) else {
        throw ValidationError.usage
    }
    let url = URL(fileURLWithPath: CommandLine.arguments[2])
    if CommandLine.arguments.count == 5 {
        guard CommandLine.arguments[3] == "--not-before",
              let threshold = TimeInterval(CommandLine.arguments[4]) else {
            throw ValidationError.usage
        }
        let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
        guard modified.timeIntervalSince1970 >= threshold else {
            throw ValidationError.invalid("report predates this capture run")
        }
    }
    let data = try Data(contentsOf: url)
    let report = try JSONDecoder().decode(Report.self, from: data)
    guard !report.events.isEmpty else {
        throw ValidationError.invalid("report has no events")
    }
    var counts: [String: Int] = [:]
    for row in report.events {
        guard row.count > 0 else {
            throw ValidationError.invalid("\(row.event) has a non-positive sample count")
        }
        counts[row.event, default: 0] += row.count
    }
    try require(counts, "launch", atLeast: 1)
    try require(counts, "mainWindow", atLeast: 1)
    switch mode {
    case "synthetic":
        try require(counts, "pdfOpen", atLeast: 4)
        try require(counts, "firstPageDisplay", atLeast: 4)
    case "documents":
        try require(counts, "pdfOpen", atLeast: 2)
        try require(counts, "webDocumentPreparation", atLeast: 4)
        try require(counts, "epubPreparation", atLeast: 2)
        try require(counts, "docxPreparation", atLeast: 2)
        try require(counts, "webOpen", atLeast: 4)
        try require(counts, "webContentReady", atLeast: 4)
        try require(counts, "epubContentReady", atLeast: 2)
        try require(counts, "docxContentReady", atLeast: 2)
    case "private":
        try require(counts, "pdfOpen", atLeast: 2)
        try require(counts, "webOpen", atLeast: 4)
        try require(counts, "webContentReady", atLeast: 4)
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
