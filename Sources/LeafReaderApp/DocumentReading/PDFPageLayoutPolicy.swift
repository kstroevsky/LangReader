import PDFKit

enum PDFPageLayoutPolicy {
    static func displayMode(isTwoPage: Bool) -> PDFDisplayMode {
        isTwoPage ? .twoUpContinuous : .singlePageContinuous
    }

    static func isTwoPage(_ displayMode: PDFDisplayMode) -> Bool {
        switch displayMode {
        case .twoUp, .twoUpContinuous:
            return true
        case .singlePage, .singlePageContinuous:
            return false
        @unknown default:
            return false
        }
    }

    static func isContinuous(_ displayMode: PDFDisplayMode) -> Bool {
        switch displayMode {
        case .singlePageContinuous, .twoUpContinuous:
            return true
        case .singlePage, .twoUp:
            return false
        @unknown default:
            return false
        }
    }
}
