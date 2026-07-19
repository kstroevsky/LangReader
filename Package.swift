// swift-tools-version: 5.10

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
        .macOS(.v12)
    ],
    products: [
        .executable(name: "LeafReaderApp", targets: ["LeafReaderApp"])
    ],
    targets: [
        .executableTarget(
            name: "LeafReaderApp",
            path: "Sources/LeafReaderApp",
            exclude: [
                "App/Assets",
                "App/Info.plist",
                "Resources"
            ],
            swiftSettings: [
                .unsafeFlags(["-F", sparkleHome])
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Cocoa"),
                .linkedFramework("CryptoKit"),
                .linkedFramework("Network"),
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
