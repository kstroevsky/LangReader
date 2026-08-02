import CoreGraphics
import Foundation

package struct StoredPDFWordRect: Codable, Equatable, Sendable {
    package let x: CGFloat
    package let y: CGFloat
    package let width: CGFloat
    package let height: CGFloat

    package init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
    }

    package var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}
