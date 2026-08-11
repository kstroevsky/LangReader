import Foundation
import NaturalLanguage
import LeafReaderCore

private func alphabeticSuffix(_ value: Int) -> String {
    var value = value
    var characters: [Character] = []
    repeat {
        characters.append(Character(UnicodeScalar(97 + (value % 26))!))
        value /= 26
    } while value > 0
    return String(characters.reversed())
}

@main
struct VocabularyIndexBenchmark {
    static func main() throws {
        let pageCount = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 300
        let groupCount = CommandLine.arguments.dropFirst(2).first.flatMap(Int.init) ?? 2_000
        let iterations = CommandLine.arguments.dropFirst(3).first.flatMap(Int.init) ?? 5
        guard pageCount > 0, groupCount > 0, iterations > 0 else {
            fputs("usage: benchmark_vocabulary_index [pages] [groups] [iterations]\n", stderr)
            exit(2)
        }

        let vocabulary = (0..<120).map { "wort\(alphabeticSuffix($0))" }
        let pages = (0..<pageCount).map { pageIndex in
            (0..<300).map { vocabulary[($0 + pageIndex) % vocabulary.count] }.joined(separator: " ")
        }
        let groups = Dictionary(uniqueKeysWithValues: (0..<groupCount).map { index in
            let word = index < vocabulary.count ? vocabulary[index] : "fehlend\(alphabeticSuffix(index))"
            return (VocabularyTextPolicy.canonicalVocabularyKey(word), word)
        })

        let buildStartedAt = ProcessInfo.processInfo.systemUptime
        guard let index = VocabularyDocumentLemmaIndex(texts: pages, language: .german) else {
            throw NSError(domain: "LeafReaderVocabularyIndexBenchmark", code: 1)
        }
        let buildMS = (ProcessInfo.processInfo.systemUptime - buildStartedAt) * 1_000
        print("build,\(pageCount),\(groupCount),\(buildMS)")

        for iteration in 0..<iterations {
            let startedAt = ProcessInfo.processInfo.systemUptime
            let results = index.matches(lemmasByKey: groups)
            let elapsedMS = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
            let matches = results.reduce(into: 0) { pageTotal, page in
                pageTotal += page.values.reduce(0) { $0 + $1.count }
            }
            print("lookup,\(iteration),\(matches),\(elapsedMS)")
        }

        for (label, lemma) in [("common", vocabulary[0]), ("missing", "nichtvorhanden")] {
            for iteration in 0..<iterations {
                let startedAt = ProcessInfo.processInfo.systemUptime
                let matches = index.matches(lemma: lemma, selectedForm: lemma)
                    .reduce(into: 0) { $0 += $1.count }
                let elapsedMS = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
                print("single-\(label),\(iteration),\(matches),\(elapsedMS)")
            }
        }
    }
}
