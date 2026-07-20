// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "RuntimeE2EHarness",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "RuntimeE2ECore", targets: ["RuntimeE2ECore"]),
        .executable(name: "RuntimeE2ECoreChecks", targets: ["RuntimeE2ECoreChecks"]),
        .executable(name: "RuntimeE2EHarness", targets: ["RuntimeE2EHarness"])
    ],
    targets: [
        .target(name: "RuntimeE2ECore"),
        .executableTarget(
            name: "RuntimeE2ECoreChecks",
            dependencies: ["RuntimeE2ECore"]
        ),
        .executableTarget(
            name: "RuntimeE2EHarness",
            dependencies: ["RuntimeE2ECore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio")
            ]
        )
    ]
)
