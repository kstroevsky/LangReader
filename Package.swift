// swift-tools-version: 6.0

import Foundation
import PackageDescription

let repositoryRoot = FileManager.default.currentDirectoryPath
let sparkleCandidates = [
    ProcessInfo.processInfo.environment["SPARKLE_HOME"],
    "/opt/homebrew/Caskroom/sparkle/2.9.2",
    "\(repositoryRoot)/Leaf Vocabulary.app/Contents/Frameworks"
].compactMap { $0 }
let sparkleHome = sparkleCandidates.first {
    FileManager.default.fileExists(atPath: "\($0)/Sparkle.framework")
} ?? sparkleCandidates[0]

let package = Package(
    name: "LeafReader",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LeafReaderApp", targets: ["LeafReaderApp"])
    ],
    targets: [
        // The platform-neutral core. It links no UI framework, so anything that
        // reaches for AppKit, PDFKit or WebKit fails here rather than in review.
        //
        // The shipping build compiles the core as a real, separate module too:
        // `scripts/build_app.sh` builds it via `scripts/build_core_module.sh`
        // (Swift 6, `-package-name LeafReader`) and links the app against it, so
        // the boundary the compiler enforces here is the same one the app binary
        // is built on — not just a check. This SwiftPM manifest is what
        // `swift build` and the portability check use; the two stay in step.
        .target(
            name: "LeafReaderCore",
            path: "Sources/LeafReaderCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "LeafReaderApp",
            dependencies: ["LeafReaderCore"],
            path: "Sources/LeafReaderApp",
            exclude: [
                "App/Assets",
                "App/Info.plist",
                "Resources"
            ],
            swiftSettings: [
                .unsafeFlags(["-F", sparkleHome]),
                // The app is still Swift 5: it is full of AppKit callbacks that
                // Swift 6 would want isolation annotations for. The core is
                // already .v6, so the strictness arrives one target at a time.
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Cocoa"),
                .linkedFramework("CryptoKit"),
                .linkedFramework("Network"),
                .linkedFramework("NaturalLanguage"),
                .linkedFramework("PDFKit"),
                .linkedFramework("WebKit"),
                .linkedLibrary("sqlite3"),
                .unsafeFlags([
                    "-F", sparkleHome,
                    "-framework", "Sparkle",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks"
                ])
            ]
        ),
        .testTarget(
            name: "LeafReaderCoreTests",
            dependencies: ["LeafReaderCore"],
            path: "Tests/LeafReaderCoreTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
