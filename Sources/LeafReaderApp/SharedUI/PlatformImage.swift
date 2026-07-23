#if canImport(UIKit)
import UIKit
/// The platform's bitmap image type — `UIImage` on iOS, `NSImage` on macOS.
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage
#endif

import SwiftUI

/// One image type across platforms, so views and models can hold and display a
/// cover without naming `NSImage` (which does not exist on iOS).
///
/// This is the image counterpart to `DesignColor`: the shared, platform-neutral
/// currency. *Producing* an image — rendering a PDF page, drawing a placeholder
/// — is inherently OS-specific and stays in a platform adapter
/// (`ShelfCoverLoader` on macOS); this only lets everything else pass the result
/// around and render it without a UI-framework dependency of its own.
extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}
