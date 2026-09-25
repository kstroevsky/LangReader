import Foundation
import LeafReaderValidation

@main
private enum VocabularyLexicalPartitionEvaluatorCLI {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fputs(
                "usage: evaluate-vocabulary-lexical-partitions <fixture.json> <report.json>\n",
                stderr
            )
            exit(2)
        }
        let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let reportURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let fixtureData = try Data(contentsOf: fixtureURL)
        let reportData = try evaluateVocabularyLexicalPartitionFixture(fixtureData)
        try reportData.write(to: reportURL, options: .atomic)
    }
}
