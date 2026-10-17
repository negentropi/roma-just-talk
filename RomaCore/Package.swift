// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RomaCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "RomaCore",
            targets: ["RomaCore"]
        ),
        .executable(
            name: "RomaCoreChecks",
            targets: ["RomaCoreChecks"]
        ),
        .executable(
            name: "RomaAudioProof",
            targets: ["RomaAudioProof"]
        )
    ],
    dependencies: [.package(path: "../RomaNVIDIA")],
    targets: [
        .target(
            name: "RomaCore",
            dependencies: [.product(name: "RomaNVIDIA", package: "RomaNVIDIA")]
        ),
        .executableTarget(
            name: "RomaAudioProof",
            dependencies: ["RomaCore"]
        ),
        .executableTarget(
            name: "RomaCoreChecks",
            dependencies: ["RomaCore"],
            path: "Tests/RomaCoreTests"
        )
    ]
)
