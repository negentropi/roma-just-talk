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
        )
    ],
    targets: [
        .target(
            name: "VoiceInkCore"
        )
    ]
)
