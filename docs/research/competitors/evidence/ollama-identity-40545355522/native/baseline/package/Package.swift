// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "WritingOllamaProbe", platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "Dependencies/VoiceInkCore"),
        .package(url: "https://github.com/tisfeng/AXSwift.git", exact: "0.3.6"),
        .package(url: "https://github.com/grpc/grpc-swift-2.git", exact: "2.4.3"),
        .package(url: "https://github.com/negentropi/grpc-swift-nio-transport.git", revision: "65adb0bc4721a6c4695e1956af9552970c06a59f"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", exact: "2.4.1"),
        .package(url: "https://github.com/jordanbaird/KeySender", exact: "0.0.5"),
        .package(url: "https://github.com/Beingpax/LLMkit.git", branch: "main"),
        .package(url: "https://github.com/tisfeng/SelectedTextKit", exact: "2.6.2"),
        .package(url: "https://github.com/apple/swift-algorithms.git", exact: "1.2.1"),
        .package(url: "https://github.com/apple/swift-asn1.git", exact: "1.7.2"),
        .package(url: "https://github.com/apple/swift-async-algorithms.git", exact: "1.1.5"),
        .package(url: "https://github.com/apple/swift-atomics.git", exact: "1.3.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", exact: "1.21.1"),
        .package(url: "https://github.com/apple/swift-collections.git", exact: "1.6.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.2"),
        .package(url: "https://github.com/apple/swift-http-structured-headers.git", exact: "1.7.0"),
        .package(url: "https://github.com/apple/swift-http-types.git", exact: "1.8.0"),
        .package(url: "https://github.com/apple/swift-log.git", exact: "1.16.2"),
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.104.0"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", exact: "1.35.2"),
        .package(url: "https://github.com/apple/swift-nio-http2.git", exact: "1.46.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", exact: "2.37.5"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", exact: "1.28.0"),
        .package(url: "https://github.com/apple/swift-numerics", exact: "1.1.1"),
        .package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.38.1"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", exact: "2.13.0"),
        .package(url: "https://github.com/apple/swift-system.git", exact: "1.8.1")
    ], targets: [.executableTarget(name: "WritingOllamaProbe", dependencies: [
        .product(name: "VoiceInkCore", package: "VoiceInkCore"),
        .product(name: "LLMkit", package: "LLMkit"),
        .product(name: "SelectedTextKit", package: "SelectedTextKit")
    ])], swiftLanguageVersions: [.v5])
