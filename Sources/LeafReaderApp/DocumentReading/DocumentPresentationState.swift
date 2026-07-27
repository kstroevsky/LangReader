import Cocoa
import LeafReaderCore

/// Content-derived presentation data for the current Document Session.
///
/// This is deliberately separate from `DocumentSession`: a table of contents and crop boxes
/// describe the rendered document, while `DocumentSession` owns its identity and lifecycle.
struct DocumentPresentationState {
    var currentDocumentDiagnostics: [String] = []
    var currentTOCItems: [ReaderTOCItem] = []
    var pdfTOCDestinations: [String: ReaderTOCHelper.PDFTOCDestination] = [:]
    var pdfTOCGeneration = 0
    var originalPDFCropBoxes: [Int: CGRect] = [:]

    mutating func resetForDocumentChange() {
        currentDocumentDiagnostics = []
        currentTOCItems = []
        pdfTOCDestinations = [:]
        pdfTOCGeneration += 1
        originalPDFCropBoxes = [:]
    }
}
