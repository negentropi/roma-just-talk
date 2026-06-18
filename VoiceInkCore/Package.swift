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
        ),
        .executable(
            name: "VoiceInkAudioProof",
            targets: ["VoiceInkAudioProof"]
        )
    ],
    targets: [
        .target(
            name: "VoiceInkCore"
        ),
        .executableTarget(
            name: "VoiceInkAudioProof",
            dependencies: ["VoiceInkCore"]
        ),
        .executableTarget(
            name: "VoiceInkCoreChecks",
            dependencies: ["VoiceInkCore"],
            path: "Tests/VoiceInkCoreTests"
        )
    ]
)
