import CryptoKit
import Foundation

package struct VocabularyDiagnosticArtifacts: Sendable {
    package let jsonData: Data
    package let markdown: String
    package let timingData: Data

    package init(jsonData: Data, markdown: String, timingData: Data) {
        self.jsonData = jsonData
        self.markdown = markdown
        self.timingData = timingData
    }

    package static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
