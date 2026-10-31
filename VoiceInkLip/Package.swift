// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceInkLip",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VoiceInkLip", targets: ["VoiceInkLip"]),
        .executable(name: "LipDictationProof", targets: ["LipDictationProof"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/microsoft/onnxruntime-swift-package-manager",
            exact: "1.24.2"
        )
    ],
    targets: [
        .target(
            name: "CLipInference",
            dependencies: [
                .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager")
            ]
        ),
        .target(
            name: "VoiceInkLip",
            dependencies: ["CLipInference"],
            resources: [.copy("Resources")]
        ),
        .executableTarget(name: "LipDictationProof", dependencies: ["VoiceInkLip"]),
        .testTarget(name: "VoiceInkLipTests", dependencies: ["VoiceInkLip"])
    ]
)
