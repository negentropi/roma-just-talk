import Foundation
import UniformTypeIdentifiers
import RomaCore

final class StoredAudioFileTests: XCTestCase {
    func testRecordingsDirectoryNameMatchesExistingStoragePath() {
        XCTAssertEqual(RomaStoredAudioFile.recordingsDirectoryName, "Recordings")
    }

    func testRecordingsDirectoryBuildsUnderBaseDirectory() {
        let baseDirectory = URL(fileURLWithPath: "/tmp/RomaJustTalk", isDirectory: true)

        XCTAssertEqual(
            RomaStoredAudioFile.recordingsDirectory(in: baseDirectory).path,
            "/tmp/RomaJustTalk/Recordings"
        )
    }

    func testCreateRecordingsDirectoryCreatesDirectoryUnderBaseDirectory() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RomaCore.StoredAudioFileTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let directory = try RomaStoredAudioFile.createRecordingsDirectory(in: baseDirectory)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(directory.lastPathComponent, "Recordings")
    }

    func testIOSStorageDirectoriesUseDocumentsDirectoryForRecordingsAndModels() {
        let documentsDirectory = URL(fileURLWithPath: "/tmp/RomaJustTalk/Documents", isDirectory: true)

        XCTAssertEqual(
            RomaIOSStorageDirectories.recordingsDirectory(in: documentsDirectory),
            RomaStoredAudioFile.recordingsDirectory(in: documentsDirectory)
        )
        XCTAssertEqual(
            RomaIOSStorageDirectories.modelsDirectory(in: documentsDirectory),
            RomaWhisperModelFiles.modelsDirectory(in: documentsDirectory)
        )
    }

    func testIOSStorageDirectoriesPrepareRecordingAndModelDirectories() throws {
        let documentsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RomaCore.IOSStorageDirectoriesTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: documentsDirectory) }

        let recordingsDirectory = RomaIOSStorageDirectories.preparedRecordingsDirectory(in: documentsDirectory)
        let modelsDirectory = RomaIOSStorageDirectories.preparedModelsDirectory(in: documentsDirectory)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordingsDirectory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(recordingsDirectory.lastPathComponent, RomaStoredAudioFile.recordingsDirectoryName)

        isDirectory = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: modelsDirectory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(modelsDirectory.lastPathComponent, RomaWhisperModelFiles.modelsDirectoryName)
    }

    func testMacOSStorageDirectoriesUseApplicationSupportBaseForAppRecordingsModelsAndCustomSounds() {
        let applicationSupportBaseDirectory = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)
        let appSupportDirectory = RomaMacOSStorageDirectories.appSupportDirectory(
            in: applicationSupportBaseDirectory
        )

        XCTAssertEqual(
            appSupportDirectory,
            RomaAppIdentity.macOSApplicationSupportDirectory(in: applicationSupportBaseDirectory)
        )
        XCTAssertEqual(
            RomaMacOSStorageDirectories.recordingsDirectory(in: appSupportDirectory),
            RomaStoredAudioFile.recordingsDirectory(in: appSupportDirectory)
        )
        XCTAssertEqual(
            RomaMacOSStorageDirectories.modelsDirectory(in: appSupportDirectory),
            RomaWhisperModelFiles.modelsDirectory(in: appSupportDirectory)
        )
        XCTAssertEqual(
            RomaMacOSStorageDirectories.customSoundsDirectory(in: applicationSupportBaseDirectory).path,
            "/tmp/Application Support/RomaJustTalk/CustomSounds"
        )
    }

    func testIOSResetPlanPreservesRecordFileAndSettingsResetOrder() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/recordings", isDirectory: true)
        let modelsDirectory = URL(fileURLWithPath: "/tmp/models", isDirectory: true)
        let cachesDirectory = URL(fileURLWithPath: "/tmp/caches", isDirectory: true)
        let temporaryDirectory = URL(fileURLWithPath: "/tmp/app-tmp", isDirectory: true)

        let filePlan = RomaAppDataResetFilePlan.iOS(
            recordingsDirectory: recordingsDirectory,
            modelsDirectory: modelsDirectory,
            cachesDirectory: cachesDirectory,
            temporaryDirectory: temporaryDirectory
        )

        XCTAssertEqual(
            appDataResetRuntimeEvents(for: RomaAppDataResetPlan.iOS(
                recordingsDirectory: recordingsDirectory,
                modelsDirectory: modelsDirectory,
                cachesDirectory: cachesDirectory,
                temporaryDirectory: temporaryDirectory
            )),
            [
                "deleteTranscriptionRecords",
                cleanFilesEvent(for: filePlan),
                "resetAppSettings"
            ]
        )

        let defaultFilePlan = RomaAppDataResetFilePlan.iOS(
            recordingsDirectory: RomaIOSStorageDirectories.recordingsDirectory,
            modelsDirectory: RomaIOSStorageDirectories.modelsDirectory,
            cachesDirectory: RomaIOSStorageDirectories.cachesDirectory,
            temporaryDirectory: RomaIOSStorageDirectories.temporaryDirectory
        )

        XCTAssertEqual(
            appDataResetRuntimeEvents(for: RomaAppDataResetPlan.iOS()),
            [
                "deleteTranscriptionRecords",
                cleanFilesEvent(for: defaultFilePlan),
                "resetAppSettings"
            ]
        )
        XCTAssertEqual(
            RomaIOSStorageDirectories.temporaryDirectory,
            URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        )
    }

    func testIOSResetPlanAppliesRuntimeStateInOrder() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/recordings", isDirectory: true)
        let modelsDirectory = URL(fileURLWithPath: "/tmp/models", isDirectory: true)
        let cachesDirectory = URL(fileURLWithPath: "/tmp/caches", isDirectory: true)
        let temporaryDirectory = URL(fileURLWithPath: "/tmp/app-tmp", isDirectory: true)
        var events: [String] = []

        RomaAppDataResetPlan.iOS(
            recordingsDirectory: recordingsDirectory,
            modelsDirectory: modelsDirectory,
            cachesDirectory: cachesDirectory,
            temporaryDirectory: temporaryDirectory
        )
        .applyRuntimeState(
            deleteTranscriptionRecords: {
                events.append("deleteTranscriptionRecords")
            },
            cleanFiles: { filePlan in
                let directoryNames = filePlan.directoriesToRemove
                    .map(\.lastPathComponent)
                    .joined(separator: ",")
                events.append("cleanFiles:\(directoryNames)")
            },
            resetAppSettings: {
                events.append("resetAppSettings")
            }
        )

        XCTAssertEqual(events, [
            "deleteTranscriptionRecords",
            "cleanFiles:recordings,models",
            "resetAppSettings"
        ])
    }

    private func appDataResetRuntimeEvents(for plan: RomaAppDataResetPlan) -> [String] {
        var events: [String] = []

        plan.applyRuntimeState(
            deleteTranscriptionRecords: {
                events.append("deleteTranscriptionRecords")
            },
            cleanFiles: { filePlan in
                events.append(cleanFilesEvent(for: filePlan))
            },
            resetAppSettings: {
                events.append("resetAppSettings")
            }
        )

        return events
    }

    private func cleanFilesEvent(for filePlan: RomaAppDataResetFilePlan) -> String {
        let removed = filePlan.directoriesToRemove.map(\.lastPathComponent).joined(separator: ",")
        let emptied = filePlan.directoriesToEmpty.map(\.lastPathComponent).joined(separator: ",")
        return "cleanFiles:\(removed):\(emptied)"
    }

    func testIOSResetFilePlanPreservesExistingDirectoryPolicy() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/recordings", isDirectory: true)
        let modelsDirectory = URL(fileURLWithPath: "/tmp/models", isDirectory: true)
        let cachesDirectory = URL(fileURLWithPath: "/tmp/caches", isDirectory: true)
        let temporaryDirectory = URL(fileURLWithPath: "/tmp/app-tmp", isDirectory: true)

        let plan = RomaAppDataResetFilePlan.iOS(
            recordingsDirectory: recordingsDirectory,
            modelsDirectory: modelsDirectory,
            cachesDirectory: cachesDirectory,
            temporaryDirectory: temporaryDirectory
        )

        XCTAssertEqual(plan.directoriesToRemove, [recordingsDirectory, modelsDirectory])
        XCTAssertEqual(plan.directoriesToEmpty, [cachesDirectory, temporaryDirectory])
    }

    func testResetFilePlanRemovesDirectoriesAndEmptiesCacheDirectoriesBestEffort() throws {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("RomaCore.StoredAudioFileTests.AppDataReset.\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: baseDirectory) }

        let recordingsDirectory = baseDirectory.appendingPathComponent("Recordings", isDirectory: true)
        let modelsDirectory = baseDirectory.appendingPathComponent("Models", isDirectory: true)
        let cachesDirectory = baseDirectory.appendingPathComponent("Caches", isDirectory: true)
        let temporaryDirectory = baseDirectory.appendingPathComponent("Temporary", isDirectory: true)

        for directory in [recordingsDirectory, modelsDirectory, cachesDirectory, temporaryDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("data".utf8).write(to: directory.appendingPathComponent("item.txt"))
        }

        RomaAppDataResetFilePlan.iOS(
            recordingsDirectory: recordingsDirectory,
            modelsDirectory: modelsDirectory,
            cachesDirectory: cachesDirectory,
            temporaryDirectory: temporaryDirectory
        )
        .performBestEffort(fileManager: fileManager)

        XCTAssertFalse(fileManager.fileExists(atPath: recordingsDirectory.path))
        XCTAssertFalse(fileManager.fileExists(atPath: modelsDirectory.path))
        XCTAssertTrue(fileManager.fileExists(atPath: cachesDirectory.path))
        XCTAssertTrue(fileManager.fileExists(atPath: temporaryDirectory.path))
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: cachesDirectory.path), [])
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: temporaryDirectory.path), [])
    }

    func testFileURLBuildsUnderRecordingsDirectory() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/RomaJustTalk/Recordings", isDirectory: true)

        XCTAssertEqual(
            RomaStoredAudioFile.fileURL(forFilename: "recording.wav", in: recordingsDirectory).path,
            "/tmp/RomaJustTalk/Recordings/recording.wav"
        )
    }

    func testRecordingFileURLUsesMacOSUUIDWAVName() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/RomaJustTalk/Recordings", isDirectory: true)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

        XCTAssertEqual(
            RomaStoredAudioFile.recordingFileURL(in: recordingsDirectory, id: id).lastPathComponent,
            "00000000-0000-0000-0000-000000000123.wav"
        )
    }

    func testTimestampedRecordingFileURLPreservesIOSName() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/RomaJustTalk/Recordings", isDirectory: true)
        let date = Date(timeIntervalSince1970: 1_234.9)

        XCTAssertEqual(
            RomaStoredAudioFile.timestampedRecordingFileURL(in: recordingsDirectory, date: date).lastPathComponent,
            "recording_1234.wav"
        )
    }

    func testImportedTranscriptionFileURLPreservesMacOSName() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/RomaJustTalk/Recordings", isDirectory: true)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000456")!

        XCTAssertEqual(
            RomaStoredAudioFile.importedTranscriptionFileURL(in: recordingsDirectory, id: id).lastPathComponent,
            "transcribed_00000000-0000-0000-0000-000000000456.wav"
        )
    }

    func testRetranscriptionFileURLPreservesMacOSName() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/RomaJustTalk/Recordings", isDirectory: true)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000789")!

        XCTAssertEqual(
            RomaStoredAudioFile.retranscriptionFileURL(in: recordingsDirectory, id: id).lastPathComponent,
            "retranscribed_00000000-0000-0000-0000-000000000789.wav"
        )
    }

    func testResolvesFileURLString() {
        let fileURL = URL(fileURLWithPath: "/tmp/roma-recording.m4a")

        XCTAssertEqual(
            RomaStoredAudioFile.resolvedURL(for: fileURL.absoluteString)?.path,
            fileURL.path
        )
    }

    func testResolvesAbsolutePath() {
        XCTAssertEqual(
            RomaStoredAudioFile.resolvedURL(for: "/tmp/roma-recording.m4a")?.path,
            "/tmp/roma-recording.m4a"
        )
    }

    func testResolvesRelativeFilenameAgainstRecordingsDirectory() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/Recordings", isDirectory: true)

        XCTAssertEqual(
            RomaStoredAudioFile
                .resolvedURL(for: "roma-recording.m4a", relativeTo: recordingsDirectory)?
                .path,
            "/tmp/Recordings/roma-recording.m4a"
        )
    }

    func testRejectsBlankAndRelativeValueWithoutDirectory() {
        XCTAssertNil(RomaStoredAudioFile.resolvedURL(for: "  "))
        XCTAssertNil(RomaStoredAudioFile.resolvedURL(for: "roma-recording.m4a"))
    }

    func testExistingURLReturnsNilForMissingFile() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/Recordings", isDirectory: true)

        XCTAssertNil(
            RomaStoredAudioFile.existingURL(
                for: "missing-recording.m4a",
                relativeTo: recordingsDirectory
            )
        )
    }

    func testExistingURLReturnsResolvedFileWhenItExists() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RomaCore.StoredAudioFileTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let recordingsDirectory = try RomaStoredAudioFile.createRecordingsDirectory(in: baseDirectory)
        let fileURL = RomaStoredAudioFile.fileURL(forFilename: "roma-recording.m4a", in: recordingsDirectory)
        try Data().write(to: fileURL)

        XCTAssertEqual(
            RomaStoredAudioFile.existingURL(
                for: "roma-recording.m4a",
                relativeTo: recordingsDirectory
            )?.path,
            fileURL.path
        )
    }

    func testAvailabilityReturnsMissingPathForBlankOrUnresolvableStoredValue() {
        XCTAssertEqual(RomaStoredAudioFile.availability(for: "  "), .missingPath)
        XCTAssertEqual(RomaStoredAudioFile.availability(for: "roma-recording.m4a"), .missingPath)
    }

    func testAvailabilityReturnsMissingFileForResolvedMissingFile() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/Recordings", isDirectory: true)
        let expectedURL = RomaStoredAudioFile.fileURL(forFilename: "missing-recording.m4a", in: recordingsDirectory)

        XCTAssertEqual(
            RomaStoredAudioFile.availability(
                for: "missing-recording.m4a",
                relativeTo: recordingsDirectory
            ),
            .missingFile(expectedURL)
        )
    }

    func testAvailabilityReturnsAvailableResolvedFileWhenItExists() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RomaCore.StoredAudioFileTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let recordingsDirectory = try RomaStoredAudioFile.createRecordingsDirectory(in: baseDirectory)
        let fileURL = RomaStoredAudioFile.fileURL(forFilename: "roma-recording.m4a", in: recordingsDirectory)
        try Data().write(to: fileURL)

        XCTAssertEqual(
            RomaStoredAudioFile.availability(
                for: "roma-recording.m4a",
                relativeTo: recordingsDirectory
            ),
            .available(fileURL)
        )
    }

    func testAvailabilityPresentationKeepsExistingIOSMissingAudioText() {
        XCTAssertEqual(RomaStoredAudioAvailability.available(URL(fileURLWithPath: "/tmp/a.wav")).unavailableTitle, nil)
        XCTAssertEqual(RomaStoredAudioAvailability.available(URL(fileURLWithPath: "/tmp/a.wav")).unavailableDetail, nil)
        XCTAssertEqual(RomaStoredAudioAvailability.unavailableSystemImageName, "exclamationmark")
        XCTAssertEqual(RomaStoredAudioAvailability.missingFile(URL(fileURLWithPath: "/tmp/missing.wav")).unavailableTitle, "Audio Unavailable")
        XCTAssertEqual(RomaStoredAudioAvailability.missingFile(URL(fileURLWithPath: "/tmp/missing.wav")).unavailableDetail, "File not found")
        XCTAssertEqual(RomaStoredAudioAvailability.missingPath.unavailableTitle, "Audio Unavailable")
        XCTAssertEqual(RomaStoredAudioAvailability.missingPath.unavailableDetail, "Path missing")
    }

    func testAvailabilityAudioSectionVisibilityPreservesMissingAudioIntent() {
        XCTAssertTrue(RomaStoredAudioAvailability.available(URL(fileURLWithPath: "/tmp/a.wav")).shouldShowAudioSection(duration: 0))
        XCTAssertTrue(RomaStoredAudioAvailability.missingFile(URL(fileURLWithPath: "/tmp/missing.wav")).shouldShowAudioSection(duration: 0))
        XCTAssertTrue(RomaStoredAudioAvailability.missingPath.shouldShowAudioSection(duration: 1))
        XCTAssertFalse(RomaStoredAudioAvailability.missingPath.shouldShowAudioSection(duration: 0))
        XCTAssertFalse(RomaStoredAudioAvailability.missingPath.shouldShowAudioSection(duration: -1))
    }

    func testDeleteExistingFileRemovesResolvedFileAndReturnsURL() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RomaCore.StoredAudioFileTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let recordingsDirectory = try RomaStoredAudioFile.createRecordingsDirectory(in: baseDirectory)
        let fileURL = RomaStoredAudioFile.fileURL(forFilename: "roma-recording.m4a", in: recordingsDirectory)
        try Data().write(to: fileURL)

        let deletedURL = try RomaStoredAudioFile.deleteExistingFile(
            for: "roma-recording.m4a",
            relativeTo: recordingsDirectory
        )

        XCTAssertEqual(deletedURL?.path, fileURL.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testDeleteExistingFileReturnsNilForMissingFile() throws {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/Recordings", isDirectory: true)

        let deletedURL = try RomaStoredAudioFile.deleteExistingFile(
            for: "missing-recording.m4a",
            relativeTo: recordingsDirectory
        )

        XCTAssertNil(deletedURL)
    }

    func testStoredAudioRecordUsesDefaultRecordingsDirectory() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/RomaJustTalk/Recordings", isDirectory: true)
        let record = StubStoredAudioRecord(
            audioFileURL: "roma-recording.m4a",
            storedAudioRecordingsDirectory: recordingsDirectory
        )

        XCTAssertEqual(
            record.resolvedAudioFileURL()?.path,
            "/tmp/RomaJustTalk/Recordings/roma-recording.m4a"
        )
    }

    func testStoredAudioRecordAllowsExplicitRecordingsDirectoryOverride() {
        let defaultDirectory = URL(fileURLWithPath: "/tmp/default/Recordings", isDirectory: true)
        let overrideDirectory = URL(fileURLWithPath: "/tmp/override/Recordings", isDirectory: true)
        let record = StubStoredAudioRecord(
            audioFileURL: "roma-recording.m4a",
            storedAudioRecordingsDirectory: defaultDirectory
        )

        XCTAssertEqual(
            record.resolvedAudioFileURL(relativeTo: overrideDirectory)?.path,
            "/tmp/override/Recordings/roma-recording.m4a"
        )
    }

    func testStoredAudioRecordDeleteUsesResolvedRecordFile() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RomaCore.StoredAudioFileTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let recordingsDirectory = try RomaStoredAudioFile.createRecordingsDirectory(in: baseDirectory)
        let fileURL = RomaStoredAudioFile.fileURL(forFilename: "roma-recording.m4a", in: recordingsDirectory)
        try Data().write(to: fileURL)
        let record = StubStoredAudioRecord(
            audioFileURL: "roma-recording.m4a",
            storedAudioRecordingsDirectory: recordingsDirectory
        )

        XCTAssertTrue(record.hasStoredAudioFile())
        XCTAssertEqual(record.storedAudioAvailability(), .available(fileURL))
        XCTAssertEqual(try record.deleteExistingAudioFile()?.path, fileURL.path)
        XCTAssertFalse(record.hasStoredAudioFile())
    }

    func testStoredAudioRecordReportingDeleteRemovesFileWithoutReportingFailure() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RomaCore.StoredAudioFileTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let recordingsDirectory = try RomaStoredAudioFile.createRecordingsDirectory(in: baseDirectory)
        let fileURL = RomaStoredAudioFile.fileURL(forFilename: "roma-recording.m4a", in: recordingsDirectory)
        try Data().write(to: fileURL)
        let record = StubStoredAudioRecord(
            audioFileURL: "roma-recording.m4a",
            storedAudioRecordingsDirectory: recordingsDirectory
        )
        var messages: [String] = []

        XCTAssertEqual(
            record.deleteExistingAudioFileReportingFailure(reportFailure: { messages.append($0) })?.path,
            fileURL.path
        )
        XCTAssertTrue(messages.isEmpty)
        XCTAssertFalse(record.hasStoredAudioFile())
    }

    func testStoredAudioRecordReportingDeleteReportsSharedFailureText() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RomaCore.StoredAudioFileTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let recordingsDirectory = try RomaStoredAudioFile.createRecordingsDirectory(in: baseDirectory)
        let fileURL = RomaStoredAudioFile.fileURL(forFilename: "roma-recording.m4a", in: recordingsDirectory)
        try Data().write(to: fileURL)
        let record = StubStoredAudioRecord(
            audioFileURL: "roma-recording.m4a",
            storedAudioRecordingsDirectory: recordingsDirectory
        )
        var messages: [String] = []

        let deletedURL = record.deleteExistingAudioFileReportingFailure(
            fileManager: FailingRemoveFileManager(),
            reportFailure: { messages.append($0) }
        )

        XCTAssertNil(deletedURL)
        XCTAssertEqual(messages, ["Error deleting audio file: blocked"])
        XCTAssertTrue(record.hasStoredAudioFile())
    }

    func testStoredAudioRecordDeleteAndClearOnlyClearsReferenceWhenFileWasDeleted() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RomaCore.StoredAudioFileTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let recordingsDirectory = try RomaStoredAudioFile.createRecordingsDirectory(in: baseDirectory)
        let fileURL = RomaStoredAudioFile.fileURL(forFilename: "roma-recording.m4a", in: recordingsDirectory)
        try Data().write(to: fileURL)
        let record = StubStoredAudioRecord(
            audioFileURL: "roma-recording.m4a",
            storedAudioRecordingsDirectory: recordingsDirectory
        )

        XCTAssertEqual(try record.deleteExistingAudioFileAndClearReference()?.path, fileURL.path)
        XCTAssertNil(record.audioFileURL)
        XCTAssertNil(try record.deleteExistingAudioFileAndClearReference())

        record.audioFileURL = "missing-recording.m4a"
        XCTAssertNil(try record.deleteExistingAudioFileAndClearReference())
        XCTAssertEqual(record.audioFileURL, "missing-recording.m4a")
    }

    func testSupportedMediaImportTypePoliciesPreserveMacOSShellIdentifiers() {
        XCTAssertEqual(
            RomaSupportedMedia.contentTypes.map { $0.identifier },
            [UTType.audio.identifier, UTType.movie.identifier]
        )
        XCTAssertEqual(
            RomaSupportedMedia.openPanelContentTypes.map { $0.identifier },
            RomaSupportedMedia.contentTypes.map { $0.identifier }
        )
        XCTAssertEqual(
            RomaSupportedMedia.dropContentTypes.map { $0.identifier },
            [
                UTType.fileURL.identifier,
                UTType.data.identifier,
                UTType.audio.identifier,
                UTType.movie.identifier
            ]
        )
        XCTAssertEqual(RomaSupportedMedia.legacyDropFileURLTypeIdentifier, "public.file-url")
        XCTAssertEqual(
            RomaSupportedMedia.dropProviderTypeIdentifiers,
            [
                UTType.fileURL.identifier,
                UTType.audio.identifier,
                UTType.movie.identifier,
                UTType.data.identifier,
                "public.file-url"
            ]
        )
    }

    func testAudioFileQueueStatusCancelingProcessingResetsOnlyProcessingItems() {
        XCTAssertEqual(
            RomaAudioFileQueueStatus.processing(phase: .transcribing).statusAfterCancelingProcessing,
            .pending
        )
        XCTAssertEqual(RomaAudioFileQueueStatus.pending.statusAfterCancelingProcessing, .pending)
        XCTAssertEqual(RomaAudioFileQueueStatus.completed.statusAfterCancelingProcessing, .completed)
        XCTAssertEqual(
            RomaAudioFileQueueStatus.failed(message: "No model").statusAfterCancelingProcessing,
            .failed(message: "No model")
        )
    }

    func testAudioFileQueuePolicyKeepsOnlyExistingSupportedNonActivePaths() {
        let activeURL = URL(fileURLWithPath: "/tmp/active.wav")
        let completedURL = URL(fileURLWithPath: "/tmp/completed.wav")
        let failedURL = URL(fileURLWithPath: "/tmp/failed.wav")
        let processingURL = URL(fileURLWithPath: "/tmp/processing.wav")
        let unsupportedURL = URL(fileURLWithPath: "/tmp/notes.txt")
        let missingURL = URL(fileURLWithPath: "/tmp/missing.m4a")
        let freshURL = URL(fileURLWithPath: "/tmp/fresh.MOV")

        let existingItems = [
            RomaAudioFileQueueItemFacts(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                standardizedPath: activeURL.standardizedFileURL.path,
                status: .pending
            ),
            RomaAudioFileQueueItemFacts(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                standardizedPath: completedURL.standardizedFileURL.path,
                status: .completed
            ),
            RomaAudioFileQueueItemFacts(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                standardizedPath: failedURL.standardizedFileURL.path,
                status: .failed(message: "No model")
            ),
            RomaAudioFileQueueItemFacts(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                standardizedPath: processingURL.standardizedFileURL.path,
                status: .processing(phase: .transcribing)
            )
        ]

        let additions = RomaAudioFileQueuePolicy.eligibleAdditionURLs(
            from: [
                RomaAudioFileQueueCandidate(url: activeURL, fileExists: true, isSupported: true),
                RomaAudioFileQueueCandidate(url: completedURL, fileExists: true, isSupported: true),
                RomaAudioFileQueueCandidate(url: failedURL, fileExists: true, isSupported: true),
                RomaAudioFileQueueCandidate(url: processingURL, fileExists: true, isSupported: true),
                RomaAudioFileQueueCandidate(url: unsupportedURL, fileExists: true, isSupported: false),
                RomaAudioFileQueueCandidate(url: missingURL, fileExists: false, isSupported: true),
                RomaAudioFileQueueCandidate(url: freshURL, fileExists: true, isSupported: true)
            ],
            existingItems: existingItems
        )

        XCTAssertEqual(additions, [completedURL, failedURL, freshURL])
    }

    func testAudioFileQueuePolicyPreservesMutationDecisions() {
        let pendingId = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let processingId = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
        let failedId = UUID(uuidString: "00000000-0000-0000-0000-000000000013")!
        let missingId = UUID(uuidString: "00000000-0000-0000-0000-000000000014")!
        let items = [
            RomaAudioFileQueueItemFacts(
                id: processingId,
                standardizedPath: "/tmp/processing.wav",
                status: .processing(phase: .loading)
            ),
            RomaAudioFileQueueItemFacts(
                id: pendingId,
                standardizedPath: "/tmp/pending.wav",
                status: .pending
            ),
            RomaAudioFileQueueItemFacts(
                id: failedId,
                standardizedPath: "/tmp/failed.wav",
                status: .failed(message: "No model")
            )
        ]

        XCTAssertTrue(RomaAudioFileQueuePolicy.canRemoveItem(id: pendingId, from: items))
        XCTAssertFalse(RomaAudioFileQueuePolicy.canRemoveItem(id: failedId, from: items))
        XCTAssertFalse(RomaAudioFileQueuePolicy.canRemoveItem(id: missingId, from: items))
        XCTAssertEqual(RomaAudioFileQueuePolicy.statusAfterRetryRequest(.failed(message: "No model")), .pending)
        XCTAssertNil(RomaAudioFileQueuePolicy.statusAfterRetryRequest(.completed))
        XCTAssertEqual(RomaAudioFileQueuePolicy.nextPendingItemID(in: items), pendingId)
        XCTAssertTrue(RomaAudioFileQueuePolicy.hasPendingItems(in: items))
        XCTAssertEqual(
            RomaAudioFileQueuePolicy.statusesAfterCancelingProcessing(items.map(\.status)),
            [.pending, .pending, .failed(message: "No model")]
        )
    }

    func testSupportedFileExtensionsPreserveMacOSImportPolicy() {
        XCTAssertEqual(
            RomaSupportedMedia.fileExtensions,
            [
                "wav", "mp3", "m4a", "aiff", "mp4", "mov", "aac", "flac", "caf",
                "amr", "ogg", "oga", "opus", "3gp"
            ]
        )
    }

    func testSupportedMediaDisplayExtensionsMatchAcceptedExtensions() {
        XCTAssertEqual(
            Set(RomaSupportedMedia.displayFileExtensions.map { $0.lowercased() }),
            RomaSupportedMedia.fileExtensions
        )
    }

    func testSupportedFileExtensionLookupIsCaseInsensitive() {
        XCTAssertTrue(RomaSupportedMedia.isSupportedFileExtension("WAV"))
        XCTAssertTrue(RomaSupportedMedia.isSupportedFileExtension("m4a"))
        XCTAssertFalse(RomaSupportedMedia.isSupportedFileExtension("txt"))
    }

    func testSupportedURLAcceptsKnownExtensions() {
        XCTAssertTrue(
            RomaSupportedMedia.isSupported(
                url: URL(fileURLWithPath: "/tmp/recording.MOV")
            )
        )
    }

    func testSupportedURLRejectsUnknownExtensionWithoutContentType() {
        XCTAssertFalse(
            RomaSupportedMedia.isSupported(
                url: URL(fileURLWithPath: "/tmp/recording.roma-unknown")
            )
        )
    }
}

private final class FailingRemoveFileManager: FileManager {
    override func removeItem(at URL: URL) throws {
        throw NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.fileWriteNoPermission.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "blocked"]
        )
    }
}

private final class StubStoredAudioRecord: RomaStoredAudioRecord {
    var audioFileURL: String?
    let storedAudioRecordingsDirectory: URL?

    init(audioFileURL: String?, storedAudioRecordingsDirectory: URL?) {
        self.audioFileURL = audioFileURL
        self.storedAudioRecordingsDirectory = storedAudioRecordingsDirectory
    }
}
