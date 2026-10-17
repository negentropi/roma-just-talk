// swift-tools-version: 6.2
import PackageDescription

// Stage complete RomaQwen, RomaCore and RomaNVIDIA packages as siblings in this directory.
let package = Package(
    name: "QwenRuntimeProbe",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "RomaQwen"), .package(path: "RomaCore")],
    targets: [
        .executableTarget(name: "QwenRuntimeProbe", dependencies: [
            .product(name: "RomaQwen", package: "romaqwen"),
            .product(name: "RomaCore", package: "romacore")
        ], path: "Sources")
    ]
)
