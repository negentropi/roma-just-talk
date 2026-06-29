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

    func testImportedLocalModelNamesToAddSkipsExistingRegistryModelsAndDownloadedDuplicates() {
        let localModels = [
            VoiceInkWhisperLocalModelFile(
                name: "ggml-base",
                url: URL(fileURLWithPath: "/tmp/ggml-base.bin")
            ),
            VoiceInkWhisperLocalModelFile(
                name: "custom-a",
                url: URL(fileURLWithPath: "/tmp/custom-a.bin")
            ),
            VoiceInkWhisperLocalModelFile(
                name: "custom-a",
                url: URL(fileURLWithPath: "/tmp/custom-a-copy.bin")
            ),
            VoiceInkWhisperLocalModelFile(
                name: "custom-b",
                url: URL(fileURLWithPath: "/tmp/custom-b.bin")
            )
        ]

        XCTAssertEqual(
            VoiceInkWhisperModelFiles.importedLocalModelNamesToAdd(
                downloadedLocalModels: localModels,
                existingModelNames: ["ggml-base", "parakeet-tdt-0.6b-v2"]
            ),
            ["custom-a", "custom-b"]
        )
    }

    func testDownloadedLocalModelFileUsesFirstDownloadedNameMatch() throws {
        let firstURL = URL(fileURLWithPath: "/tmp/custom-a.bin")
        let secondURL = URL(fileURLWithPath: "/tmp/custom-a-copy.bin")
        let first = VoiceInkWhisperLocalModelFile(name: "custom-a", url: firstURL)
        let second = VoiceInkWhisperLocalModelFile(name: "custom-a", url: secondURL)

        XCTAssertEqual(
            VoiceInkWhisperModelFiles.downloadedLocalModelFile(
                forModelName: "custom-a",
                in: [first, second]
            ),
            first
        )
        XCTAssertNil(
            VoiceInkWhisperModelFiles.downloadedLocalModelFile(
                forModelName: "missing",
                in: [first, second]
            )
        )
    }

    func testAvailableLocalModelFileURLFindsExistingImportedModel() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.WhisperModelFilesTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let modelsDirectory = try VoiceInkWhisperModelFiles.createModelsDirectory(in: baseDirectory)
        let modelURL = modelsDirectory.appendingPathComponent("custom-model.bin")
        try Data("model".utf8).write(to: modelURL)

        let localModels = [
            VoiceInkWhisperLocalModelFile(name: "other-model", url: modelsDirectory.appendingPathComponent("other-model.bin")),
            VoiceInkWhisperLocalModelFile(name: "custom-model", url: modelURL)
        ]

        XCTAssertEqual(
            VoiceInkWhisperModelFiles.availableLocalModelFileURL(
                forModelName: "custom-model",
                in: localModels
            ),
            modelURL
        )
    }

    func testAvailableLocalModelFileURLRejectsMissingNamesAndFiles() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.WhisperModelFilesTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let modelsDirectory = try VoiceInkWhisperModelFiles.createModelsDirectory(in: baseDirectory)
        let missingURL = modelsDirectory.appendingPathComponent("custom-model.bin")
        let localModels = [
            VoiceInkWhisperLocalModelFile(name: "custom-model", url: missingURL)
        ]

        XCTAssertNil(
            VoiceInkWhisperModelFiles.availableLocalModelFileURL(
                forModelName: "custom-model",
                in: localModels
            )
        )
        XCTAssertNil(
            VoiceInkWhisperModelFiles.availableLocalModelFileURL(
                forModelName: "missing-model",
                in: localModels
            )
        )
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

    func testWriteDownloadedLocalModelDataBuildsSharedLocalModelFile() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.WhisperModelFilesTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let modelsDirectory = VoiceInkWhisperModelFiles.modelsDirectory(in: baseDirectory)
        let modelFile = try VoiceInkWhisperModelFiles.writeDownloadedLocalModelData(
            Data("model".utf8),
            forModelName: "ggml-base",
            in: modelsDirectory
        )

        XCTAssertEqual(modelFile.name, "ggml-base")
        XCTAssertEqual(modelFile.url, VoiceInkWhisperModelFiles.fileURL(forModelName: "ggml-base", in: modelsDirectory))
        XCTAssertEqual(String(data: try Data(contentsOf: modelFile.url), encoding: .utf8), "model")
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

    func testDownloadCompletionPolicyClassifiesResponseAndTemporaryFile() {
        let url = URL(string: "https://example.com/ggml-base.bin")!
        let temporaryURL = URL(fileURLWithPath: "/tmp/ggml-base.download")
        func response(statusCode: Int) -> HTTPURLResponse {
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        }

        XCTAssertEqual(
            VoiceInkWhisperModelDownloadResponsePolicy.completion(
                temporaryURL: temporaryURL,
                response: response(statusCode: 200)
            ),
            .ready(temporaryURL)
        )
        XCTAssertEqual(
            VoiceInkWhisperModelDownloadResponsePolicy.completion(
                temporaryURL: temporaryURL,
                response: response(statusCode: 500)
            ),
            .serverError
        )
        XCTAssertEqual(
            VoiceInkWhisperModelDownloadResponsePolicy.completion(
                temporaryURL: nil,
                response: response(statusCode: 200)
            ),
            .missingTemporaryFile
        )
        XCTAssertEqual(
            VoiceInkWhisperModelDownloadResponsePolicy.completion(
                temporaryURL: nil,
                response: nil
            ),
            .serverError
        )
    }

    func testSimpleDownloadCompletionPlanOwnsIOSFailureAndInstallDecisions() {
        let url = URL(string: "https://example.com/ggml-base.bin")!
        let temporaryURL = URL(fileURLWithPath: "/tmp/ggml-base.download")
        let networkError = NSError(
            domain: "VoiceInkCoreTests",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Offline"]
        )
        func response(statusCode: Int) -> HTTPURLResponse {
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        }

        assertSimpleDownloadCompletionEvents(
            VoiceInkWhisperModelSimpleDownloadCompletionPlan.completion(
                temporaryURL: temporaryURL,
                response: response(statusCode: 200),
                error: nil
            ),
            expectedEvents: ["install:ggml-base.download"]
        )
        assertSimpleDownloadCompletionEvents(
            VoiceInkWhisperModelSimpleDownloadCompletionPlan.completion(
                temporaryURL: temporaryURL,
                response: response(statusCode: 200),
                error: networkError
            ),
            expectedEvents: ["failure:downloadFailed-Offline"]
        )
        assertSimpleDownloadCompletionEvents(
            VoiceInkWhisperModelSimpleDownloadCompletionPlan.completion(
                temporaryURL: temporaryURL,
                response: response(statusCode: 500),
                error: nil
            ),
            expectedEvents: ["failure:serverErrorDuringDownload"]
        )
        assertSimpleDownloadCompletionEvents(
            VoiceInkWhisperModelSimpleDownloadCompletionPlan.completion(
                temporaryURL: nil,
                response: response(statusCode: 200),
                error: nil
            ),
            expectedEvents: ["failure:noFileReceived"]
        )
    }

    func testSimpleDownloadCompletionPlanIgnoresCancellation() {
        let temporaryURL = URL(fileURLWithPath: "/tmp/ggml-base.download")
        let cancelledURLSessionError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCancelled
        )

        assertSimpleDownloadCompletionEvents(
            VoiceInkWhisperModelSimpleDownloadCompletionPlan.completion(
                temporaryURL: temporaryURL,
                response: nil,
                error: cancelledURLSessionError
            ),
            expectedEvents: ["cancel"]
        )

        assertSimpleDownloadCompletionEvents(
            VoiceInkWhisperModelSimpleDownloadCompletionPlan.completion(
                temporaryURL: temporaryURL,
                response: nil,
                error: CancellationError()
            ),
            expectedEvents: ["cancel"]
        )
    }

    func testSimpleDownloadCompletionPlanAppliesRuntimeState() {
        let temporaryURL = URL(fileURLWithPath: "/tmp/ggml-base.download")
        let plans: [VoiceInkWhisperModelSimpleDownloadCompletionPlan] = [
            VoiceInkWhisperModelSimpleDownloadCompletionPlan.completion(
                temporaryURL: temporaryURL,
                response: HTTPURLResponse(
                    url: URL(string: "https://example.com/ggml-base.bin")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                ),
                error: nil
            ),
            VoiceInkWhisperModelSimpleDownloadCompletionPlan.completion(
                temporaryURL: nil,
                response: HTTPURLResponse(
                    url: URL(string: "https://example.com/ggml-base.bin")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                ),
                error: nil
            ),
            VoiceInkWhisperModelSimpleDownloadCompletionPlan.completion(
                temporaryURL: temporaryURL,
                response: nil,
                error: CancellationError()
            )
        ]
        var events: [String] = []

        for plan in plans {
            plan.applyRuntimeState(
                installTemporaryFile: { url in events.append("install:\(url.lastPathComponent)") },
                presentFailure: { alert in events.append("failure:\(alert.id)") },
                ignoreCancellation: { events.append("cancel") }
            )
        }

        XCTAssertEqual(events, [
            "install:ggml-base.download",
            "failure:noFileReceived",
            "cancel"
        ])
    }

    private func assertSimpleDownloadCompletionEvents(
        _ plan: VoiceInkWhisperModelSimpleDownloadCompletionPlan,
        expectedEvents: [String]
    ) {
        var events: [String] = []

        plan.applyRuntimeState(
            installTemporaryFile: { url in events.append("install:\(url.lastPathComponent)") },
            presentFailure: { alert in events.append("failure:\(alert.id)") },
            ignoreCancellation: { events.append("cancel") }
        )

        XCTAssertEqual(events, expectedEvents)
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

    func testSimpleDownloadTrackingStateOwnsIOSLifecycle() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.WhisperModelDownloadTrackingStateTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let modelsDirectory = try VoiceInkWhisperModelFiles.createModelsDirectory(in: baseDirectory)
        let model = VoiceInkWhisperModelFiles.baseModel
        var trackingState = VoiceInkWhisperModelSimpleDownloadTrackingState()

        XCTAssertTrue(trackingState.startDownload(for: model))
        XCTAssertFalse(trackingState.startDownload(for: model))
        XCTAssertTrue(trackingState.isDownloading(model))

        let startedState = trackingState.downloadState(for: model, modelsDirectory: modelsDirectory)
        XCTAssertFalse(startedState.isDownloaded)
        XCTAssertTrue(startedState.isDownloading)
        XCTAssertEqual(startedState.progress.fraction, 0)

        trackingState.updateProgress(0.42, for: model)

        let progressState = trackingState.downloadState(for: model, modelsDirectory: modelsDirectory)
        XCTAssertEqual(progressState.progress.fraction, 0.42)

        try Data().write(to: model.fileURL(in: modelsDirectory))
        trackingState.finishDownload(for: model)

        let downloadedState = trackingState.downloadState(for: model, modelsDirectory: modelsDirectory)
        XCTAssertTrue(downloadedState.isDownloaded)
        XCTAssertFalse(downloadedState.isDownloading)
        XCTAssertFalse(trackingState.isDownloading(model))

        trackingState.updateProgress(0.9, for: model)
        XCTAssertFalse(trackingState.downloadState(for: model, modelsDirectory: modelsDirectory).isDownloading)
    }

    func testSimpleDownloadTrackingStateIgnoresInactiveProgress() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.WhisperModelDownloadInactiveProgressTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let modelsDirectory = try VoiceInkWhisperModelFiles.createModelsDirectory(in: baseDirectory)
        let model = VoiceInkWhisperModelFiles.baseModel
        var trackingState = VoiceInkWhisperModelSimpleDownloadTrackingState()

        trackingState.updateProgress(0.5, for: model)

        let inactiveState = trackingState.downloadState(for: model, modelsDirectory: modelsDirectory)
        XCTAssertFalse(inactiveState.isDownloading)
        XCTAssertEqual(inactiveState.progress.fraction, 0)
    }

    func testSimpleDownloadTrackingStateCleansUpCancelledDownload() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.WhisperModelDownloadCancelTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let modelsDirectory = try VoiceInkWhisperModelFiles.createModelsDirectory(in: baseDirectory)
        let model = VoiceInkWhisperModelFiles.baseModel
        var trackingState = VoiceInkWhisperModelSimpleDownloadTrackingState()

        XCTAssertTrue(trackingState.startDownload(for: model))
        trackingState.updateProgress(0.5, for: model)
        XCTAssertTrue(trackingState.downloadState(for: model, modelsDirectory: modelsDirectory).isDownloading)

        trackingState.cancelDownload(for: model)

        XCTAssertFalse(trackingState.isDownloading(model))
        XCTAssertFalse(trackingState.downloadState(for: model, modelsDirectory: modelsDirectory).isDownloading)
        trackingState.updateProgress(0.9, for: model)
        XCTAssertEqual(
            trackingState.downloadState(for: model, modelsDirectory: modelsDirectory).progress.fraction,
            0
        )
    }

    func testManagementSnapshotBuildsAvailabilityPathStateAndRows() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.WhisperModelManagementSnapshotTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let modelsDirectory = try VoiceInkWhisperModelFiles.createModelsDirectory(in: baseDirectory)
        let model = VoiceInkWhisperModelFiles.baseModel
        var trackingState = VoiceInkWhisperModelSimpleDownloadTrackingState()
        XCTAssertTrue(trackingState.startDownload(for: model))
        trackingState.updateProgress(0.25, for: model)

        let downloadingSnapshot = VoiceInkWhisperModelManagementSnapshot(
            modelsDirectory: modelsDirectory,
            downloadTrackingState: trackingState,
            models: [model]
        )

        XCTAssertFalse(downloadingSnapshot.hasAvailableModel())
        XCTAssertNil(downloadingSnapshot.modelPath(forRuntimeModelName: VoiceInkTranscriptionModelCatalog.localBaseModel))
        XCTAssertEqual(
            downloadingSnapshot.downloadState(for: model),
            VoiceInkWhisperModelDownloadState(
                isDownloaded: false,
                progress: .simple(modelName: model.modelName, isDownloading: true, progress: 0.25)
            )
        )
        XCTAssertEqual(downloadingSnapshot.managementRows(), [downloadingSnapshot.managementRow(for: model)])
        XCTAssertEqual(downloadingSnapshot.managementRow(for: model).presentation.action, .downloading)

        try Data().write(to: model.fileURL(in: modelsDirectory))
        trackingState.finishDownload(for: model)
        let downloadedSnapshot = VoiceInkWhisperModelManagementSnapshot(
            modelsDirectory: modelsDirectory,
            downloadTrackingState: trackingState,
            models: [model]
        )

        XCTAssertTrue(downloadedSnapshot.hasAvailableModel())
        XCTAssertEqual(
            downloadedSnapshot.modelPath(forRuntimeModelName: VoiceInkTranscriptionModelCatalog.localBaseModel),
            model.fileURL(in: modelsDirectory).path
        )
        XCTAssertEqual(downloadedSnapshot.managementRow(for: model).presentation.action, .downloaded)
    }

    func testModelManagementDiagnosticsPreserveIOSLogCopy() {
        let downloadURL = URL(string: "https://example.com/ggml-base.bin")!

        XCTAssertEqual(
            VoiceInkWhisperModelManagementDiagnostics.alreadyDownloadingMessage(modelName: "ggml-base"),
            "Model ggml-base is already being downloaded."
        )
        XCTAssertEqual(
            VoiceInkWhisperModelManagementDiagnostics.startingDownloadMessage(
                modelName: "ggml-base",
                downloadURL: downloadURL
            ),
            "Starting download of ggml-base from https://example.com/ggml-base.bin."
        )
        XCTAssertEqual(
            VoiceInkWhisperModelManagementDiagnostics.downloadFailedMessage(
                modelName: "ggml-base",
                alertMessage: "No file received"
            ),
            "Download failed for ggml-base: No file received"
        )
        XCTAssertEqual(
            VoiceInkWhisperModelManagementDiagnostics.downloadCancelledMessage(modelName: "ggml-base"),
            "Download cancelled for ggml-base."
        )
        XCTAssertEqual(
            VoiceInkWhisperModelManagementDiagnostics.downloadedMessage(
                modelName: "ggml-base",
                finalPath: "/tmp/ggml-base.bin"
            ),
            "Successfully downloaded ggml-base to /tmp/ggml-base.bin."
        )
        XCTAssertEqual(
            VoiceInkWhisperModelManagementDiagnostics.saveFailedMessage(
                modelName: "ggml-base",
                localizedDescription: "Permission denied"
            ),
            "Failed to save ggml-base: Permission denied"
        )
        XCTAssertEqual(
            VoiceInkWhisperModelManagementDiagnostics.notDownloadedMessage(modelName: "ggml-base"),
            "Model ggml-base is not downloaded."
        )
        XCTAssertEqual(
            VoiceInkWhisperModelManagementDiagnostics.deletedMessage(modelName: "ggml-base"),
            "Successfully deleted model ggml-base."
        )
        XCTAssertEqual(
            VoiceInkWhisperModelManagementDiagnostics.deleteFailedMessage(
                modelName: "ggml-base",
                localizedDescription: "File is locked"
            ),
            "Failed to delete model ggml-base: File is locked"
        )
    }

    func testSimpleDownloadStateBuildsSharedRowPresentation() {
        let model = VoiceInkWhisperModelFiles.baseModel
        let downloadingState = VoiceInkWhisperModelDownloadState(
            isDownloaded: false,
            progress: .simple(modelName: model.modelName, isDownloading: true, progress: 0.25)
        )

        let downloadingPresentation = downloadingState.rowPresentation(for: model)
        XCTAssertEqual(downloadingPresentation.title, model.displayName)
        XCTAssertEqual(downloadingPresentation.subtitle, model.description)
        XCTAssertEqual(
            downloadingPresentation.downloadButtonTitle,
            VoiceInkWhisperModelDownloadProgress.downloadActionTitle(for: model)
        )
        XCTAssertEqual(downloadingPresentation.progress, downloadingState.progress)
        XCTAssertTrue(downloadingPresentation.shouldShowProgress)
        XCTAssertTrue(downloadingPresentation.shouldShowCircularProgressAccessory)
        XCTAssertEqual(downloadingPresentation.actionTint, .destructive)

        let downloadedState = VoiceInkWhisperModelDownloadState(isDownloaded: true, progress: .simple(
            modelName: model.modelName,
            isDownloading: false,
            progress: nil
        ))
        let downloadedPresentation = downloadedState.rowPresentation(for: model)
        XCTAssertEqual(downloadedPresentation.actionSystemImageName, "checkmark.circle.fill")
        XCTAssertFalse(downloadedPresentation.shouldShowCircularProgressAccessory)
        XCTAssertEqual(downloadedPresentation.actionTint, .success)

        let idleState = VoiceInkWhisperModelDownloadState(isDownloaded: false, progress: .simple(
            modelName: model.modelName,
            isDownloading: false,
            progress: nil
        ))
        let idlePresentation = idleState.rowPresentation(for: model)
        XCTAssertEqual(idlePresentation.actionSystemImageName, "icloud.and.arrow.down")
        XCTAssertEqual(idlePresentation.downloadButtonSystemImageName, "arrow.down.circle.fill")
        XCTAssertFalse(idlePresentation.shouldShowProgress)
        XCTAssertFalse(idlePresentation.shouldShowCircularProgressAccessory)
        XCTAssertEqual(idlePresentation.actionTint, .primary)
        XCTAssertEqual(downloadingPresentation.actionSystemImageName, "xmark.circle.fill")
    }

    func testSimpleDownloadRowPresentationBuildsDeferredRuntimeAction() {
        let model = VoiceInkWhisperModelFiles.baseModel
        let downloadedPresentation = VoiceInkWhisperModelDownloadState(
            isDownloaded: true,
            progress: .simple(modelName: model.modelName, isDownloading: false, progress: nil)
        ).rowPresentation(for: model)
        let idlePresentation = VoiceInkWhisperModelDownloadState(
            isDownloaded: false,
            progress: .simple(modelName: model.modelName, isDownloading: false, progress: nil)
        ).rowPresentation(for: model)
        let downloadingPresentation = VoiceInkWhisperModelDownloadState(
            isDownloaded: false,
            progress: .simple(modelName: model.modelName, isDownloading: true, progress: 0.5)
        ).rowPresentation(for: model)
        var events: [String] = []

        XCTAssertNil(downloadedPresentation.runtimeAction(
            requestDownload: { events.append("download") },
            cancelDownload: { events.append("cancel") }
        ))
        XCTAssertTrue(events.isEmpty)

        let downloadAction = idlePresentation.runtimeAction(
            requestDownload: { events.append("download") },
            cancelDownload: { events.append("cancel") }
        )
        XCTAssertTrue(events.isEmpty)
        downloadAction?()
        XCTAssertEqual(events, ["download"])

        let cancelAction = downloadingPresentation.runtimeAction(
            requestDownload: { events.append("download") },
            cancelDownload: { events.append("cancel") }
        )
        cancelAction?()
        XCTAssertEqual(events, ["download", "cancel"])
    }

    func testSimpleDownloadManagementListBuildsSharedRows() {
        let model = VoiceInkWhisperModelFiles.baseModel
        let downloadState = VoiceInkWhisperModelDownloadState(
            isDownloaded: true,
            progress: .simple(modelName: model.modelName, isDownloading: false, progress: nil)
        )
        let row = VoiceInkWhisperModelManagementList.row(for: model, downloadState: downloadState)
        let rows = VoiceInkWhisperModelManagementList.rows(for: [model]) { _ in downloadState }

        XCTAssertEqual(
            row,
            VoiceInkWhisperModelManagementRow(
                model: model,
                presentation: VoiceInkWhisperModelDownloadRowPresentation(
                    title: "Whisper Base Model",
                    subtitle: "Multilingual model with good balance of speed and accuracy",
                    action: .downloaded,
                    downloadButtonTitle: "Download Model (142 MB)",
                    progress: .simple(modelName: model.modelName, isDownloading: false, progress: nil)
                ),
                downloadConfirmation: .download(for: model),
                deleteConfirmation: .delete(for: model)
            )
        )
        XCTAssertEqual(rows, [row])
        XCTAssertTrue(row.deleteRequestRuntimeAction {} != nil)

        let idleRow = VoiceInkWhisperModelManagementList.row(
            for: model,
            downloadState: VoiceInkWhisperModelDownloadState(
                isDownloaded: false,
                progress: .simple(modelName: model.modelName, isDownloading: false, progress: nil)
            )
        )
        XCTAssertNil(idleRow.deleteRequestRuntimeAction {})
    }

    func testSimpleDownloadManagementRowBuildsConfirmationRuntimeActions() {
        let model = VoiceInkWhisperModelFiles.baseModel
        let downloadedRow = VoiceInkWhisperModelManagementList.row(
            for: model,
            downloadState: VoiceInkWhisperModelDownloadState(
                isDownloaded: true,
                progress: .simple(modelName: model.modelName, isDownloading: false, progress: nil)
            )
        )
        let idleRow = VoiceInkWhisperModelManagementList.row(
            for: model,
            downloadState: VoiceInkWhisperModelDownloadState(
                isDownloaded: false,
                progress: .simple(modelName: model.modelName, isDownloading: false, progress: nil)
            )
        )
        let downloadingRow = VoiceInkWhisperModelManagementList.row(
            for: model,
            downloadState: VoiceInkWhisperModelDownloadState(
                isDownloaded: false,
                progress: .simple(modelName: model.modelName, isDownloading: true, progress: 0.5)
            )
        )
        var events: [String] = []

        let deleteRequestAction = downloadedRow.deleteRequestRuntimeAction {
            events.append("delete-request")
        }
        let confirmedDeleteAction = downloadedRow.confirmedDeleteRuntimeAction {
            events.append("delete")
        }
        let confirmedDownloadAction = idleRow.confirmedDownloadRuntimeAction {
            events.append("download")
        }

        XCTAssertTrue(deleteRequestAction != nil)
        XCTAssertTrue(confirmedDeleteAction != nil)
        XCTAssertTrue(confirmedDownloadAction != nil)
        XCTAssertNil(idleRow.deleteRequestRuntimeAction {})
        XCTAssertNil(idleRow.confirmedDeleteRuntimeAction {})
        XCTAssertNil(downloadedRow.confirmedDownloadRuntimeAction {})
        XCTAssertNil(downloadingRow.confirmedDownloadRuntimeAction {})

        deleteRequestAction?()
        confirmedDeleteAction?()
        confirmedDownloadAction?()
        XCTAssertEqual(events, ["delete-request", "delete", "download"])
    }

    func testSimpleDownloadDeletionPolicyPreservesIOSDeleteIntent() throws {
        assertDeletionPlanEvents(
            VoiceInkWhisperModelDeletionPolicy.plan(isDownloaded: false),
            expectedEvents: ["missing"]
        )
        assertDeletionPlanEvents(
            VoiceInkWhisperModelDeletionPolicy.plan(isDownloaded: true),
            expectedEvents: ["delete", "refresh"]
        )

        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.ModelDeletionPlanTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let modelsDirectory = try VoiceInkWhisperModelFiles.createModelsDirectory(in: baseDirectory)
        let model = VoiceInkWhisperModelFiles.baseModel

        XCTAssertEqual(
            deletionPlanEvents(VoiceInkWhisperModelDeletionPolicy.plan(for: model, in: modelsDirectory)),
            ["missing"]
        )

        try Data().write(to: model.fileURL(in: modelsDirectory))

        XCTAssertEqual(
            deletionPlanEvents(VoiceInkWhisperModelDeletionPolicy.plan(for: model, in: modelsDirectory)),
            ["delete", "refresh"]
        )
    }

    func testSimpleDownloadDeletionPlanAppliesRuntimeState() {
        assertDeletionPlanEvents(
            VoiceInkWhisperModelDeletionPolicy.plan(isDownloaded: false),
            expectedEvents: ["missing"]
        )
        assertDeletionPlanEvents(
            VoiceInkWhisperModelDeletionPolicy.plan(isDownloaded: true),
            expectedEvents: ["delete", "refresh"]
        )
    }

    func testSimpleDownloadDeletionPlanAppliesFailureStateWithoutRefresh() {
        let error = NSError(
            domain: "VoiceInkCoreTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Permission denied"]
        )
        var events: [String] = []

        VoiceInkWhisperModelDeletionPolicy.plan(isDownloaded: true).applyRuntimeState(
            skipMissingFile: { events.append("missing") },
            deleteDownloadedFiles: {
                events.append("delete")
                throw error
            },
            refreshAfterSuccessfulDelete: { events.append("refresh") },
            handleDeleteFailure: { error in events.append("failure:\(error.localizedDescription)") }
        )

        XCTAssertEqual(events, ["delete", "failure:Permission denied"])
    }

    private func assertDeletionPlanEvents(
        _ plan: VoiceInkWhisperModelDeletionPlan,
        expectedEvents: [String]
    ) {
        XCTAssertEqual(deletionPlanEvents(plan), expectedEvents)
    }

    private func deletionPlanEvents(_ plan: VoiceInkWhisperModelDeletionPlan) -> [String] {
        var events: [String] = []

        plan.applyRuntimeState(
            skipMissingFile: { events.append("missing") },
            deleteDownloadedFiles: { events.append("delete") },
            refreshAfterSuccessfulDelete: { events.append("refresh") },
            handleDeleteFailure: { error in events.append("failure:\(error.localizedDescription)") }
        )

        return events
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
