import Foundation
import XCTest
import VoiceInkCore
@testable import VoiceInk_ios

final class IOSLocalWhisperModelImporterTests: XCTestCase {
    func testImportCopiesAndNormalizesSecurityScopedModelFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IOSLocalWhisperModelImporterTests.\(UUID().uuidString)")
        let sourceDirectory = root.appendingPathComponent("Source", isDirectory: true)
        let modelsDirectory = root.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = sourceDirectory.appendingPathComponent("Custom-Finetune.BIN")
        let modelData = Data([0x67, 0x67, 0x6D, 0x6C])
        try modelData.write(to: sourceURL)

        let outcome = IOSLocalWhisperModelImporter.importModel(
            from: sourceURL,
            into: modelsDirectory
        )

        guard case .imported(let model) = outcome else {
            return XCTFail("Expected imported model, got \(outcome)")
        }
        XCTAssertEqual(model.name, "Custom-Finetune")
        XCTAssertEqual(model.url.lastPathComponent, "Custom-Finetune.bin")
        XCTAssertEqual(try Data(contentsOf: model.url), modelData)
    }

    func testImportReportsDuplicateAndUnsupportedFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IOSLocalWhisperModelImporterTests.\(UUID().uuidString)")
        let modelsDirectory = root.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(
            at: modelsDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appendingPathComponent("custom.bin")
        try Data([1]).write(to: sourceURL)
        try Data([2]).write(to: modelsDirectory.appendingPathComponent("custom.bin"))

        XCTAssertEqual(
            IOSLocalWhisperModelImporter.importModel(
                from: sourceURL,
                into: modelsDirectory
            ),
            .duplicate(filename: "custom.bin")
        )
        XCTAssertEqual(
            IOSLocalWhisperModelImporter.importModel(
                from: root.appendingPathComponent("notes.txt"),
                into: modelsDirectory
            ),
            .unsupportedFile
        )
    }
}
