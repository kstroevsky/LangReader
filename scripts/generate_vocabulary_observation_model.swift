import Foundation
import LeafReaderCore

@main
struct VocabularyObservationModelGenerator {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write(
                Data("usage: generate_vocabulary_observation_model <output.json|->\n".utf8)
            )
            throw Exit.invalidArguments
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(VocabularyObservationModel.manifest())
        data.append(0x0A)
        let output = CommandLine.arguments[1]
        if output == "-" {
            FileHandle.standardOutput.write(data)
        } else {
            try data.write(to: URL(fileURLWithPath: output), options: .atomic)
        }
    }

    private enum Exit: Error {
        case invalidArguments
    }
}
