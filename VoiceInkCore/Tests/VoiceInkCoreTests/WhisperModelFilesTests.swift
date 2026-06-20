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

    func testRuntimeModelFileURLMapsLocalBaseModelToBootstrapFilename() {
        let modelsDirectory = URL(fileURLWithPath: "/tmp/VoiceInk/WhisperModels", isDirectory: true)

        XCTAssertEqual(
            VoiceInkWhisperModelFiles.fileURL(
                forRuntimeModelName: VoiceInkTranscriptionModelCatalog.localBaseModel,
                in: modelsDirectory
            ).path,
            "/tmp/VoiceInk/WhisperModels/ggml-base.bin"
        )
    }

    func testAvailableModelFileURLUsesRuntimeModelName() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.WhisperModelFilesTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let modelsDirectory = try VoiceInkWhisperModelFiles.createModelsDirectory(in: baseDirectory)
        let baseURL = VoiceInkWhisperModelFiles.baseModel.fileURL(in: modelsDirectory)

        XCTAssertNil(VoiceInkWhisperModelFiles.availableModelFileURL(
            forRuntimeModelName: VoiceInkTranscriptionModelCatalog.localBaseModel,
            in: modelsDirectory
        ))

        try Data().write(to: baseURL)

        XCTAssertEqual(
            VoiceInkWhisperModelFiles.availableModelFileURL(
                forRuntimeModelName: VoiceInkTranscriptionModelCatalog.localBaseModel,
                in: modelsDirectory
            ),
            baseURL
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
        XCTAssertEqual(VoiceInkWhisperModelFiles.modelFileExtension, "bin")
        XCTAssertTrue(VoiceInkWhisperModelFiles.isModelFile(URL(fileURLWithPath: "/tmp/ggml-base.bin")))
        XCTAssertFalse(VoiceInkWhisperModelFiles.isModelFile(URL(fileURLWithPath: "/tmp/ggml-base.BIN")))
        XCTAssertFalse(VoiceInkWhisperModelFiles.isModelFile(URL(fileURLWithPath: "/tmp/ggml-base.txt")))
    }

    func testImportableModelFilePreservesMacOSCaseInsensitiveImportPolicy() {
        XCTAssertTrue(VoiceInkWhisperModelFiles.isImportableModelFile(URL(fileURLWithPath: "/tmp/ggml-base.bin")))
        XCTAssertTrue(VoiceInkWhisperModelFiles.isImportableModelFile(URL(fileURLWithPath: "/tmp/ggml-base.BIN")))
        XCTAssertFalse(VoiceInkWhisperModelFiles.isImportableModelFile(URL(fileURLWithPath: "/tmp/ggml-base.txt")))
    }

    func testLocalModelImportPlanBuildsMacOSImportInputs() throws {
        let modelsDirectory = URL(fileURLWithPath: "/tmp/VoiceInk/WhisperModels", isDirectory: true)
        let sourceURL = URL(fileURLWithPath: "/tmp/Downloads/Custom-Whisper.BIN")
        let plan = try XCTUnwrap(
            VoiceInkWhisperModelFiles.localModelImportPlan(
                from: sourceURL,
                in: modelsDirectory
            )
        )

        XCTAssertEqual(plan.sourceURL, sourceURL)
        XCTAssertEqual(plan.modelName, "Custom-Whisper")
        XCTAssertEqual(plan.modelFilename, "Custom-Whisper.bin")
        XCTAssertEqual(plan.destinationURL.path, "/tmp/VoiceInk/WhisperModels/Custom-Whisper.bin")
        XCTAssertEqual(plan.localModelFile.name, "Custom-Whisper")
        XCTAssertEqual(plan.localModelFile.url, plan.destinationURL)
        XCTAssertFalse(plan.isDuplicate)
    }

    func testLocalModelImportPlanRejectsUnsupportedFilesAndReportsDuplicates() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.LocalModelImportPlanTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let modelsDirectory = try VoiceInkWhisperModelFiles.createModelsDirectory(in: baseDirectory)
        let sourceURL = baseDirectory.appendingPathComponent("ggml-custom.bin")
        let duplicateURL = modelsDirectory.appendingPathComponent("ggml-custom.bin")
        try Data().write(to: duplicateURL)

        XCTAssertNil(
            VoiceInkWhisperModelFiles.localModelImportPlan(
                from: baseDirectory.appendingPathComponent("notes.txt"),
                in: modelsDirectory
            )
        )
        XCTAssertTrue(
            try XCTUnwrap(
                VoiceInkWhisperModelFiles.localModelImportPlan(
                    from: sourceURL,
                    in: modelsDirectory
                )
            ).isDuplicate
        )
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

    func testDownloadResponsePolicyPreservesHTTPStatusSuccessRange() {
        let url = URL(string: "https://example.com/ggml-base.bin")!
        func response(statusCode: Int) -> HTTPURLResponse {
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        }

        XCTAssertFalse(VoiceInkWhisperModelDownloadResponsePolicy.isSuccessfulStatusCode(199))
        XCTAssertTrue(VoiceInkWhisperModelDownloadResponsePolicy.isSuccessfulStatusCode(200))
        XCTAssertTrue(VoiceInkWhisperModelDownloadResponsePolicy.isSuccessfulStatusCode(299))
        XCTAssertFalse(VoiceInkWhisperModelDownloadResponsePolicy.isSuccessfulStatusCode(300))
        XCTAssertTrue(VoiceInkWhisperModelDownloadResponsePolicy.isSuccessfulResponse(response(statusCode: 204)))
        XCTAssertFalse(VoiceInkWhisperModelDownloadResponsePolicy.isSuccessfulResponse(response(statusCode: 404)))
        XCTAssertFalse(VoiceInkWhisperModelDownloadResponsePolicy.isSuccessfulResponse(nil))
    }

    func testSimpleDownloadProgressFormatsIOSProgress() {
        let progress = VoiceInkWhisperModelDownloadProgress.simple(
            modelName: "ggml-base",
            isDownloading: true,
            progress: 0.428
        )

        XCTAssertTrue(progress.isActive)
        XCTAssertEqual(progress.fraction, 0.428, accuracy: 0.000001)
        XCTAssertEqual(progress.compactStatusText, "Downloading...")
        XCTAssertEqual(progress.percentText, "42%")
        XCTAssertEqual(progress.phaseText, "Downloading ggml-base Model")
        let idleProgress = VoiceInkWhisperModelDownloadProgress.simple(
            modelName: "ggml-base",
            isDownloading: false,
            progress: 0.5
        )
        XCTAssertEqual(idleProgress.phase, .idle)
        XCTAssertEqual(idleProgress.compactStatusText, "")
    }

    func testSimpleDownloadStateCombinesIOSDownloadedAndProgressState() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.WhisperModelDownloadStateTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let modelsDirectory = try VoiceInkWhisperModelFiles.createModelsDirectory(in: baseDirectory)
        let model = VoiceInkWhisperModelFiles.baseModel

        let missingState = VoiceInkWhisperModelDownloadState.simple(
            model: model,
            modelsDirectory: modelsDirectory,
            isDownloadingByModelID: [model.id: true],
            downloadProgressByModelID: [model.id: 0.5]
        )

        XCTAssertFalse(missingState.isDownloaded)
        XCTAssertTrue(missingState.isDownloading)
        XCTAssertEqual(missingState.progress.fraction, 0.5)

        try Data().write(to: model.fileURL(in: modelsDirectory))
        let downloadedState = VoiceInkWhisperModelDownloadState.simple(
            model: model,
            modelsDirectory: modelsDirectory,
            isDownloadingByModelID: [:],
            downloadProgressByModelID: [model.id: 0.5]
        )

        XCTAssertTrue(downloadedState.isDownloaded)
        XCTAssertFalse(downloadedState.isDownloading)
        XCTAssertEqual(downloadedState.progress.phase, .idle)
    }

    func testSimpleDownloadStateBuildsSharedRowPresentation() {
        let model = VoiceInkWhisperModelFiles.baseModel
        let downloadingState = VoiceInkWhisperModelDownloadState(
            isDownloaded: false,
            progress: .simple(modelName: model.modelName, isDownloading: true, progress: 0.25)
        )

        XCTAssertEqual(
            downloadingState.rowPresentation(for: model),
            VoiceInkWhisperModelDownloadRowPresentation(
                title: model.displayName,
                subtitle: model.description,
                action: .downloading,
                downloadButtonTitle: VoiceInkWhisperModelDownloadProgress.downloadActionTitle(for: model),
                progress: downloadingState.progress
            )
        )
        XCTAssertTrue(downloadingState.rowPresentation(for: model).shouldShowProgress)

        let downloadedState = VoiceInkWhisperModelDownloadState(isDownloaded: true, progress: .simple(
            modelName: model.modelName,
            isDownloading: false,
            progress: nil
        ))
        XCTAssertEqual(downloadedState.rowPresentation(for: model).action, .downloaded)
        XCTAssertEqual(downloadedState.rowPresentation(for: model).actionSystemImageName, "checkmark.circle.fill")

        let idleState = VoiceInkWhisperModelDownloadState(isDownloaded: false, progress: .simple(
            modelName: model.modelName,
            isDownloading: false,
            progress: nil
        ))
        XCTAssertEqual(idleState.rowPresentation(for: model).action, .download)
        XCTAssertEqual(idleState.rowPresentation(for: model).actionSystemImageName, "icloud.and.arrow.down")
        XCTAssertEqual(idleState.rowPresentation(for: model).downloadButtonSystemImageName, "arrow.down.circle.fill")
        XCTAssertFalse(idleState.rowPresentation(for: model).shouldShowProgress)
        XCTAssertEqual(downloadingState.rowPresentation(for: model).actionSystemImageName, "xmark.circle.fill")
    }

    func testMacOSDownloadProgressUsesMainAndCoreMLKeys() {
        let startingProgress = VoiceInkWhisperModelDownloadProgress.macOS(
            modelName: "ggml-base",
            downloadProgress: [
                VoiceInkWhisperModelDownloadProgress.mainProgressKey(forModelName: "ggml-base"): 0
            ]
        )
        let progress = VoiceInkWhisperModelDownloadProgress.macOS(
            modelName: "ggml-base",
            downloadProgress: [
                VoiceInkWhisperModelDownloadProgress.mainProgressKey(forModelName: "ggml-base"): 1,
                VoiceInkWhisperModelDownloadProgress.coreMLProgressKey(forModelName: "ggml-base"): 0.4
            ]
        )

        XCTAssertTrue(VoiceInkWhisperModelDownloadProgress.isMacOSDownloading(
            modelName: "ggml-base",
            downloadProgress: [
                VoiceInkWhisperModelDownloadProgress.mainProgressKey(forModelName: "ggml-base"): 1
            ]
        ))
        XCTAssertTrue(startingProgress.isActive)
        XCTAssertEqual(startingProgress.fraction, 0)
        XCTAssertEqual(startingProgress.phaseText, "Downloading ggml-base Model")
        XCTAssertEqual(progress.fraction, 0.7, accuracy: 0.000001)
        XCTAssertEqual(progress.percentText, "70%")
        XCTAssertEqual(progress.phaseText, "Downloading Core ML Model for ggml-base")
    }

    func testMacOSDownloadProgressIgnoresCoreMLForQuantizedModels() {
        let progress = VoiceInkWhisperModelDownloadProgress.macOS(
            modelName: "ggml-large-v3-turbo-q5_0",
            downloadProgress: [
                VoiceInkWhisperModelDownloadProgress.mainProgressKey(forModelName: "ggml-large-v3-turbo-q5_0"): 0.25,
                VoiceInkWhisperModelDownloadProgress.coreMLProgressKey(forModelName: "ggml-large-v3-turbo-q5_0"): 1
            ]
        )

        XCTAssertEqual(progress.fraction, 0.25, accuracy: 0.000001)
        XCTAssertEqual(progress.phaseText, "Downloading ggml-large-v3-turbo-q5_0 Model")
    }

    func testModelDownloadCopyUsesSharedModelSize() {
        let model = VoiceInkWhisperModelFiles.baseModel

        XCTAssertEqual(
            VoiceInkWhisperModelDownloadProgress.downloadActionTitle(for: model),
            "Download Model (142 MB)"
        )
        XCTAssertEqual(
            VoiceInkWhisperModelDownloadProgress.downloadConfirmationMessage(for: model),
            "To enable offline transcription, a 142 MB model needs to be downloaded. This may incur data charges if you are not on Wi-Fi."
        )
    }

    func testModelOperationConfirmationPreservesIOSDownloadAndDeleteCopy() {
        let model = VoiceInkWhisperModelFiles.baseModel
        let download = VoiceInkWhisperModelOperationConfirmationPresentation.download(for: model)
        let delete = VoiceInkWhisperModelOperationConfirmationPresentation.delete(for: model)

        XCTAssertEqual(download.id, "download-base")
        XCTAssertEqual(download.title, "Download Model")
        XCTAssertEqual(download.message, "To enable offline transcription, a 142 MB model needs to be downloaded. This may incur data charges if you are not on Wi-Fi.")
        XCTAssertEqual(download.primaryButtonTitle, "Download")
        XCTAssertEqual(download.cancelButtonTitle, "Cancel")
        XCTAssertEqual(delete.id, "delete-base")
        XCTAssertEqual(delete.title, "Delete Model")
        XCTAssertEqual(delete.message, "Delete Whisper Base Model? This will remove the model from your device.")
        XCTAssertEqual(delete.primaryButtonTitle, "Delete")
        XCTAssertEqual(delete.cancelButtonTitle, "Cancel")
    }

    func testModelOperationAlertPreservesIOSDownloadFailureCopy() {
        let alert = VoiceInkWhisperModelOperationAlertPresentation.downloadFailed(
            localizedDescription: "The request timed out."
        )

        XCTAssertEqual(alert.id, "downloadFailed-The request timed out.")
        XCTAssertEqual(alert.title, "Download Error")
        XCTAssertEqual(alert.message, "Download failed: The request timed out.")
        XCTAssertEqual(alert.primaryButtonTitle, "OK")
    }

    func testModelOperationAlertPreservesIOSServerAndMissingFileCopy() {
        XCTAssertEqual(
            VoiceInkWhisperModelOperationAlertPresentation.serverErrorDuringDownload.message,
            "Server error during download"
        )
        XCTAssertEqual(
            VoiceInkWhisperModelOperationAlertPresentation.noFileReceived.message,
            "No file received"
        )
        XCTAssertEqual(
            VoiceInkWhisperModelOperationAlertPresentation.unknownDownloadFailure.message,
            "An unknown error occurred."
        )
    }

    func testModelOperationAlertPreservesIOSSaveAndDeleteFailureCopy() {
        let saveAlert = VoiceInkWhisperModelOperationAlertPresentation.saveFailed(
            localizedDescription: "Permission denied"
        )
        let deleteAlert = VoiceInkWhisperModelOperationAlertPresentation.deleteFailed(
            localizedDescription: "File is locked"
        )

        XCTAssertEqual(saveAlert.title, "Download Error")
        XCTAssertEqual(saveAlert.message, "Failed to save model: Permission denied")
        XCTAssertEqual(deleteAlert.title, "Download Error")
        XCTAssertEqual(deleteAlert.message, "Failed to delete model: File is locked")
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
