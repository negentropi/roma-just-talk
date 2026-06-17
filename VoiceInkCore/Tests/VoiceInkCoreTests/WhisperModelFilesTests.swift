import Foundation
@testable import VoiceInkCore

final class WhisperModelFilesTests: XCTestCase {
    func testBootstrapModelsContainBaseModelSpec() {
        XCTAssertEqual(VoiceInkWhisperModelFiles.bootstrapModels, [VoiceInkWhisperModelFiles.baseModel])
        XCTAssertEqual(VoiceInkWhisperModelFiles.bootstrapModels.first?.id, VoiceInkTranscriptionModelCatalog.localBaseModel)
        XCTAssertEqual(VoiceInkWhisperModelFiles.bootstrapModels.first?.filename, "ggml-base.bin")
    }

    func testModelsDirectoryBuildsUnderPlatformBaseDirectory() throws {
        let baseDirectory = URL(fileURLWithPath: "/tmp/VoiceInk", isDirectory: true)

        XCTAssertEqual(
            VoiceInkWhisperModelFiles.modelsDirectory(in: baseDirectory).path,
            "/tmp/VoiceInk/WhisperModels"
        )
    }

    func testCreateModelsDirectoryCreatesDirectoryUnderPlatformBaseDirectory() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.WhisperModelFilesTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let directory = try VoiceInkWhisperModelFiles.createModelsDirectory(in: baseDirectory)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(directory.lastPathComponent, "WhisperModels")
    }

    func testModelFileURLBuildsUnderModelsDirectory() {
        let modelsDirectory = URL(fileURLWithPath: "/tmp/VoiceInk/WhisperModels", isDirectory: true)

        XCTAssertEqual(
            VoiceInkWhisperModelFiles.fileURL(forModelName: "ggml-base", in: modelsDirectory).path,
            "/tmp/VoiceInk/WhisperModels/ggml-base.bin"
        )
        XCTAssertEqual(
            VoiceInkWhisperModelFiles.baseModel.fileURL(in: modelsDirectory).path,
            "/tmp/VoiceInk/WhisperModels/ggml-base.bin"
        )
    }

    func testModelDownloadStateChecksSharedFileURL() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.WhisperModelFilesTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let modelsDirectory = try VoiceInkWhisperModelFiles.createModelsDirectory(in: baseDirectory)
        let model = VoiceInkWhisperModelFiles.baseModel

        XCTAssertFalse(model.isDownloaded(in: modelsDirectory))

        try Data().write(to: model.fileURL(in: modelsDirectory))
        XCTAssertTrue(model.isDownloaded(in: modelsDirectory))
    }

    func testAvailableBootstrapModelFileURLUsesFirstDownloadedBootstrapModel() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.WhisperModelFilesTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let modelsDirectory = try VoiceInkWhisperModelFiles.createModelsDirectory(in: baseDirectory)
        let model = VoiceInkWhisperModelFiles.baseModel

        XCTAssertNil(VoiceInkWhisperModelFiles.availableBootstrapModelFileURL(in: modelsDirectory))

        try Data().write(to: model.fileURL(in: modelsDirectory))

        XCTAssertEqual(
            VoiceInkWhisperModelFiles.availableBootstrapModelFileURL(in: modelsDirectory),
            model.fileURL(in: modelsDirectory)
        )
    }

    func testDeleteModelFilesRemovesMainModelAndCoreMLSidecar() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.WhisperModelFilesTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let modelsDirectory = try VoiceInkWhisperModelFiles.createModelsDirectory(in: baseDirectory)
        let modelURL = VoiceInkWhisperModelFiles.fileURL(forModelName: "ggml-base", in: modelsDirectory)
        let coreMLDirectory = try XCTUnwrap(
            VoiceInkWhisperModelFiles.coreMLEncoderDirectoryURL(forModelName: "ggml-base", in: modelsDirectory)
        )

        try Data().write(to: modelURL)
        try FileManager.default.createDirectory(at: coreMLDirectory, withIntermediateDirectories: true)

        try VoiceInkWhisperModelFiles.deleteModelFiles(
            forModelName: "ggml-base",
            modelFileURL: modelURL,
            in: modelsDirectory
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: modelURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: coreMLDirectory.path))
    }

    func testDeleteDownloadedFilesUsesModelSpecURL() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.WhisperModelFilesTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let modelsDirectory = try VoiceInkWhisperModelFiles.createModelsDirectory(in: baseDirectory)
        let model = VoiceInkWhisperModelFiles.baseModel

        try Data().write(to: model.fileURL(in: modelsDirectory))

        try model.deleteDownloadedFiles(in: modelsDirectory)

        XCTAssertFalse(model.isDownloaded(in: modelsDirectory))
    }

    func testCoreMLSidecarURLsUseSharedModelNaming() {
        let modelsDirectory = URL(fileURLWithPath: "/tmp/VoiceInk/WhisperModels", isDirectory: true)

        XCTAssertEqual(
            VoiceInkWhisperModelFiles.coreMLZipFileURL(forModelName: "ggml-base", in: modelsDirectory)?.path,
            "/tmp/VoiceInk/WhisperModels/ggml-base-encoder.mlmodelc.zip"
        )
        XCTAssertEqual(
            VoiceInkWhisperModelFiles.coreMLEncoderDirectoryURL(forModelName: "ggml-base", in: modelsDirectory)?.path,
            "/tmp/VoiceInk/WhisperModels/ggml-base-encoder.mlmodelc"
        )
        XCTAssertNil(
            VoiceInkWhisperModelFiles.coreMLZipFileURL(forModelName: "ggml-large-v3-turbo-q5_0", in: modelsDirectory)
        )
    }

    func testCoreMLSupportPolicyExcludesQuantizedModels() {
        XCTAssertTrue(VoiceInkWhisperModelFiles.supportsCoreML(forModelName: "ggml-base"))
        XCTAssertTrue(VoiceInkWhisperModelFiles.supportsCoreML(forModelName: "ggml-large-v3-turbo"))
        XCTAssertFalse(VoiceInkWhisperModelFiles.supportsCoreML(forModelName: "ggml-large-v3-turbo-q5_0"))
        XCTAssertFalse(VoiceInkWhisperModelFiles.supportsCoreML(forModelName: "ggml-large-v3-turbo-q8_0"))
    }

    func testModelFileFilterMatchesExistingBinOnlyPolicy() {
        XCTAssertTrue(VoiceInkWhisperModelFiles.isModelFile(URL(fileURLWithPath: "/tmp/ggml-base.bin")))
        XCTAssertFalse(VoiceInkWhisperModelFiles.isModelFile(URL(fileURLWithPath: "/tmp/ggml-base.BIN")))
        XCTAssertFalse(VoiceInkWhisperModelFiles.isModelFile(URL(fileURLWithPath: "/tmp/ggml-base.txt")))
    }

    func testLocalModelFileUsesExistingBinOnlyNamePolicy() throws {
        let modelURL = URL(fileURLWithPath: "/tmp/VoiceInk/WhisperModels/ggml-base.bin")
        let modelFile = try XCTUnwrap(VoiceInkWhisperModelFiles.localModelFile(from: modelURL))

        XCTAssertEqual(modelFile.name, "ggml-base")
        XCTAssertEqual(modelFile.url, modelURL)
        XCTAssertFalse(modelFile.isCoreMLDownloaded)
        XCTAssertNil(VoiceInkWhisperModelFiles.localModelFile(from: URL(fileURLWithPath: "/tmp/model.txt")))
    }

    func testLocalModelFilesReadsOnlyBinFilesFromDirectory() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.WhisperModelFilesTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let modelsDirectory = try VoiceInkWhisperModelFiles.createModelsDirectory(in: baseDirectory)
        try Data().write(to: modelsDirectory.appendingPathComponent("ggml-base.bin"))
        try Data().write(to: modelsDirectory.appendingPathComponent("notes.txt"))
        try Data().write(to: modelsDirectory.appendingPathComponent("GGML-UPPER.BIN"))

        let modelFiles = try VoiceInkWhisperModelFiles.localModelFiles(in: modelsDirectory)

        XCTAssertEqual(Set(modelFiles.map(\.name)), ["ggml-base"])
    }

    func testInstallDownloadedModelFileReplacesExistingModelFile() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.WhisperModelFilesTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let modelsDirectory = try VoiceInkWhisperModelFiles.createModelsDirectory(in: baseDirectory)
        let model = VoiceInkWhisperModelFiles.baseModel
        let finalURL = model.fileURL(in: modelsDirectory)
        let temporaryURL = baseDirectory.appendingPathComponent("download.tmp")

        try Data("old".utf8).write(to: finalURL)
        try Data("new".utf8).write(to: temporaryURL)

        let installedURL = try VoiceInkWhisperModelFiles.installDownloadedModelFile(
            model,
            fromTemporaryFile: temporaryURL,
            in: modelsDirectory
        )

        XCTAssertEqual(installedURL, finalURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryURL.path))
        XCTAssertEqual(String(data: try Data(contentsOf: finalURL), encoding: .utf8), "new")
    }

    func testWriteDownloadedModelDataUsesSharedModelNameURL() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.WhisperModelFilesTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let modelsDirectory = VoiceInkWhisperModelFiles.modelsDirectory(in: baseDirectory)

        let writtenURL = try VoiceInkWhisperModelFiles.writeDownloadedModelData(
            Data("model".utf8),
            forModelName: "ggml-base",
            in: modelsDirectory
        )

        XCTAssertEqual(writtenURL, VoiceInkWhisperModelFiles.fileURL(forModelName: "ggml-base", in: modelsDirectory))
        XCTAssertEqual(String(data: try Data(contentsOf: writtenURL), encoding: .utf8), "model")
    }

    func testDownloadableModelsMatchMacOSLocalWhisperCatalog() {
        XCTAssertEqual(
            VoiceInkWhisperModelFiles.downloadableModels.map(\.modelName),
            [
                "ggml-tiny",
                "ggml-tiny.en",
                "ggml-base",
                "ggml-base.en",
                "ggml-large-v2",
                "ggml-large-v3",
                "ggml-large-v3-turbo",
                "ggml-large-v3-turbo-q5_0"
            ]
        )

        let quantizedTurbo = VoiceInkWhisperModelFiles.downloadableModels.last
        XCTAssertEqual(quantizedTurbo?.filename, "ggml-large-v3-turbo-q5_0.bin")
        XCTAssertEqual(quantizedTurbo?.size, "547 MB")
        XCTAssertEqual(quantizedTurbo?.accuracy, 0.95)
        XCTAssertEqual(quantizedTurbo?.ramUsage, 1.0)
    }
}
