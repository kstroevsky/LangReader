import Foundation

package enum ReaderDocumentKind {
    case pdf
    case epub
    case docx

    package static func kind(for url: URL) -> ReaderDocumentKind? {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return .pdf
        case "epub":
            return .epub
        case "docx":
            return .docx
        default:
            return nil
        }
    }
}
