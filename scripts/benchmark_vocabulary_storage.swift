import Cocoa
import Foundation
import LeafReaderCore

// The production record store exposes an unrelated AI-chat projection. The
// benchmark compiles that store in isolation, so only its return shape is needed.
final class AIChatPanel {
    struct LinkedWordBubble {
        let id: String
        let word: String
        let question: String
        let answer: String
    }
}

private enum WriteMode: String {
    case serial
    case batch
}

private func records(count: Int) -> [StoredPDFWordRecord] {
    (0..<count).map { index in
        StoredPDFWordRecord(
            id: "occurrence-\(index)",
            vocabularyID: "vocabulary-\(index / 4)",
            word: "Wort\(index / 4)",
            lemma: "wort\(index / 4)",
            surfaceForm: "Wort\(index / 4)",
            pageIndex: index,
            bounds: StoredPDFWordRect(CGRect(x: 10, y: 20, width: 30, height: 12)),
            context: "Ein kurzer deutscher Beispielsatz mit Wort\(index / 4).",
            question: "",
            answer: "",
            createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
            srs: nil
        )
    }
}

private func measure(mode: WriteMode, records: [StoredPDFWordRecord]) throws -> Double {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("leafreader-vocabulary-write-benchmark-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WordRecordSQLiteStore(databaseURL: directory.appendingPathComponent("word-records.sqlite3"))
    let startedAt = ProcessInfo.processInfo.systemUptime
    let succeeded: Bool
    switch mode {
    case .serial:
        succeeded = records.allSatisfy {
            store.upsertPDFRecord(documentID: "benchmark-document", record: $0)
        }
    case .batch:
        succeeded = store.upsertPDFRecords(documentID: "benchmark-document", records: records)
    }
    guard succeeded else {
        throw NSError(domain: "LeafReaderVocabularyStorageBenchmark", code: 1)
    }
    return (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
}

@main
struct VocabularyStorageBenchmark {
    static func main() throws {
        let count = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 2_000
        let iterations = CommandLine.arguments.dropFirst(2).first.flatMap(Int.init) ?? 3
        guard count > 0, iterations > 0 else {
            fputs("usage: benchmark_vocabulary_storage [record-count] [iterations]\n", stderr)
            exit(2)
        }

        let fixture = records(count: count)
        for iteration in 0..<iterations {
            let modes: [WriteMode] = iteration.isMultiple(of: 2) ? [.serial, .batch] : [.batch, .serial]
            for mode in modes {
                let milliseconds = try measure(mode: mode, records: fixture)
                print("\(mode.rawValue),\(iteration),\(count),\(milliseconds)")
            }
        }
    }
}
