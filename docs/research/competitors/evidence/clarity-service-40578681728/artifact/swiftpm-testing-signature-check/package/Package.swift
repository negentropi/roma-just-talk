// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SignaturePreparation", platforms: [.macOS(.v14)], targets: [.testTarget(name: "SignaturePreparationTests", resources: [.process("signed-resource.txt")])], swiftLanguageVersions: [.v5])
