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
        // Note that `scripts/build_app.sh` does *not* build through SwiftPM — it
        // compiles every source as one module — so this split is a boundary
        // *proof*, run by `scripts/check.sh`, not the shipping build. That is
        // deliberate: the app keeps whole-module optimisation across the seam
        // while the compiler still refuses to let the core depend upwards.
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
        )
    ]
)
