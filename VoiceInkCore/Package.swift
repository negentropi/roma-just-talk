// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VoiceInkCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "VoiceInkCore",
            targets: ["VoiceInkCore"]
        ),
        .executable(
            name: "VoiceInkCoreChecks",
            targets: ["VoiceInkCoreChecks"]
        )
    ],
    targets: [
        .target(
            name: "VoiceInkCore"
        ),
        .executableTarget(
            name: "VoiceInkCoreChecks",
            dependencies: ["VoiceInkCore"],
            path: "Tests/VoiceInkCoreTests"
        )
    ]
)
