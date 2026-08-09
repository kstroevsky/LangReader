// swift-tools-version: 6.0

import Foundation
import PackageDescription

let repositoryRoot = FileManager.default.currentDirectoryPath
let sparkleCaskRoot = "/opt/homebrew/Caskroom/sparkle"
let sparkleCaskHomes = (try? FileManager.default.contentsOfDirectory(atPath: sparkleCaskRoot))?
    .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
    .map { "\(sparkleCaskRoot)/\($0)" } ?? []
let sparkleCandidates = [ProcessInfo.processInfo.environment["SPARKLE_HOME"]].compactMap { $0 }
    + sparkleCaskHomes
    + ["\(repositoryRoot)/Leaf Vocabulary.app/Contents/Frameworks"]
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
        // `scripts/build_app.sh` delegates compilation to this package and copies
        // the resulting product into the signed app bundle. That keeps this real
        // module boundary in shipping builds while reusing SwiftPM's persistent
        // incremental products instead of compiling every source from scratch.
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
                .swiftLanguageMode(.v6)
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
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        // App-target tests exercise the AppKit/SwiftUI ownership seam.  Core
        // tests intentionally cannot import these types.
        .testTarget(
            name: "LeafReaderAppTests",
            dependencies: ["LeafReaderApp", "LeafReaderCore"],
            path: "Tests/LeafReaderAppTests",
            swiftSettings: [
                .unsafeFlags(["-F", sparkleHome]),
                .swiftLanguageMode(.v6)
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("PDFKit"),
                .linkedFramework("WebKit"),
                .unsafeFlags([
                    "-F", sparkleHome,
                    "-framework", "Sparkle",
                    "-Xlinker", "-rpath",
                    "-Xlinker", sparkleHome
                ])
            ]
        )
    ]
)
