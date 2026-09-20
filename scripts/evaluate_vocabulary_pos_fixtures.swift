import Foundation
import LeafReaderValidation

@main
private enum VocabularyPOSEvaluator {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fputs("usage: evaluate-vocabulary-pos-fixtures <fixture.json> <report.json>\n", stderr)
            exit(2)
        }
        let fixtureData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let reportData = try evaluateVocabularyPOSFixture(fixtureData)
        try reportData.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
    }
}
