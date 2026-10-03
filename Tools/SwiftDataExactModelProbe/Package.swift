// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SwiftDataExactModelProbe",
    platforms: [.macOS("14.2.1")],
    products: [.executable(name: "voiceink-swiftdata-probe", targets: ["VoiceInk"])],
    dependencies: [.package(path: "../../VoiceInkCore")],
    targets: [
        .executableTarget(
            name: "VoiceInk",
            dependencies: [.product(name: "VoiceInkCore", package: "VoiceInkCore")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
