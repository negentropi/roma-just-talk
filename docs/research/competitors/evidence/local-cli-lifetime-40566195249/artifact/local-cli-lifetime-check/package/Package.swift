// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "LocalCLILifetime", platforms: [.macOS(.v14)], dependencies: [.package(path: "Dependencies/VoiceInkCore")], targets: [
.executableTarget(name: "OldLocalCLIProbe", dependencies: [.product(name: "VoiceInkCore", package: "VoiceInkCore")]),
.executableTarget(name: "NewLocalCLIProbe", dependencies: [.product(name: "VoiceInkCore", package: "VoiceInkCore")]),
.executableTarget(name: "RawLocalCLIProbe", dependencies: [.product(name: "VoiceInkCore", package: "VoiceInkCore")], swiftSettings: [.define("RAW_PROBE")])
], swiftLanguageVersions: [.v5])
