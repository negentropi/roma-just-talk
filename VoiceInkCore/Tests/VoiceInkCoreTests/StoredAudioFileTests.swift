import Foundation
import UniformTypeIdentifiers
import VoiceInkCore

final class StoredAudioFileTests: XCTestCase {
    func testRecordingsDirectoryNameMatchesExistingStoragePath() {
        XCTAssertEqual(VoiceInkStoredAudioFile.recordingsDirectoryName, "Recordings")
    }

    func testRecordingsDirectoryBuildsUnderBaseDirectory() {
        let baseDirectory = URL(fileURLWithPath: "/tmp/VoiceInk", isDirectory: true)

        XCTAssertEqual(
            VoiceInkStoredAudioFile.recordingsDirectory(in: baseDirectory).path,
            "/tmp/VoiceInk/Recordings"
        )
    }

    func testCreateRecordingsDirectoryCreatesDirectoryUnderBaseDirectory() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.StoredAudioFileTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let directory = try VoiceInkStoredAudioFile.createRecordingsDirectory(in: baseDirectory)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(directory.lastPathComponent, "Recordings")
    }

    func testIOSStorageDirectoriesUseDocumentsDirectoryForRecordingsAndModels() {
        let documentsDirectory = URL(fileURLWithPath: "/tmp/VoiceInk/Documents", isDirectory: true)

        XCTAssertEqual(
            VoiceInkIOSStorageDirectories.recordingsDirectory(in: documentsDirectory),
            VoiceInkStoredAudioFile.recordingsDirectory(in: documentsDirectory)
        )
        XCTAssertEqual(
            VoiceInkIOSStorageDirectories.modelsDirectory(in: documentsDirectory),
            VoiceInkWhisperModelFiles.modelsDirectory(in: documentsDirectory)
        )
    }

    func testIOSStorageDirectoriesPrepareRecordingAndModelDirectories() throws {
        let documentsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.IOSStorageDirectoriesTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: documentsDirectory) }

        let recordingsDirectory = VoiceInkIOSStorageDirectories.preparedRecordingsDirectory(in: documentsDirectory)
        let modelsDirectory = VoiceInkIOSStorageDirectories.preparedModelsDirectory(in: documentsDirectory)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordingsDirectory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(recordingsDirectory.lastPathComponent, VoiceInkStoredAudioFile.recordingsDirectoryName)

        isDirectory = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: modelsDirectory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(modelsDirectory.lastPathComponent, VoiceInkWhisperModelFiles.modelsDirectoryName)
    }

    func testMacOSStorageDirectoriesUseApplicationSupportBaseForAppRecordingsModelsAndCustomSounds() {
        let applicationSupportBaseDirectory = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)
        let appSupportDirectory = VoiceInkMacOSStorageDirectories.appSupportDirectory(
            in: applicationSupportBaseDirectory
        )

        XCTAssertEqual(
            appSupportDirectory,
            VoiceInkAppIdentity.macOSApplicationSupportDirectory(in: applicationSupportBaseDirectory)
        )
        XCTAssertEqual(
            VoiceInkMacOSStorageDirectories.recordingsDirectory(in: appSupportDirectory),
            VoiceInkStoredAudioFile.recordingsDirectory(in: appSupportDirectory)
        )
        XCTAssertEqual(
            VoiceInkMacOSStorageDirectories.modelsDirectory(in: appSupportDirectory),
            VoiceInkWhisperModelFiles.modelsDirectory(in: appSupportDirectory)
        )
        XCTAssertEqual(
            VoiceInkMacOSStorageDirectories.customSoundsDirectory(in: applicationSupportBaseDirectory).path,
            "/tmp/Application Support/VoiceInk/CustomSounds"
        )
    }

    func testIOSResetPlanPreservesRecordFileAndSettingsResetOrder() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/recordings", isDirectory: true)
        let modelsDirectory = URL(fileURLWithPath: "/tmp/models", isDirectory: true)
        let cachesDirectory = URL(fileURLWithPath: "/tmp/caches", isDirectory: true)
        let temporaryDirectory = URL(fileURLWithPath: "/tmp/app-tmp", isDirectory: true)

        let filePlan = VoiceInkAppDataResetFilePlan.iOS(
            recordingsDirectory: recordingsDirectory,
            modelsDirectory: modelsDirectory,
            cachesDirectory: cachesDirectory,
            temporaryDirectory: temporaryDirectory
        )

        XCTAssertEqual(
            VoiceInkAppDataResetPlan.iOS(
                recordingsDirectory: recordingsDirectory,
                modelsDirectory: modelsDirectory,
                cachesDirectory: cachesDirectory,
                temporaryDirectory: temporaryDirectory
            ).steps,
            [
                .deleteTranscriptionRecords,
                .cleanFiles(filePlan),
                .resetAppSettings
            ]
        )

        let defaultFilePlan = VoiceInkAppDataResetFilePlan.iOS(
            recordingsDirectory: VoiceInkIOSStorageDirectories.recordingsDirectory,
            modelsDirectory: VoiceInkIOSStorageDirectories.modelsDirectory,
            cachesDirectory: VoiceInkIOSStorageDirectories.cachesDirectory,
            temporaryDirectory: VoiceInkIOSStorageDirectories.temporaryDirectory
        )

        XCTAssertEqual(
            VoiceInkAppDataResetPlan.iOS().steps,
            [
                .deleteTranscriptionRecords,
                .cleanFiles(defaultFilePlan),
                .resetAppSettings
            ]
        )
        XCTAssertEqual(
            VoiceInkIOSStorageDirectories.temporaryDirectory,
            URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        )
    }

    func testIOSResetPlanAppliesRuntimeStateInOrder() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/recordings", isDirectory: true)
        let modelsDirectory = URL(fileURLWithPath: "/tmp/models", isDirectory: true)
        let cachesDirectory = URL(fileURLWithPath: "/tmp/caches", isDirectory: true)
        let temporaryDirectory = URL(fileURLWithPath: "/tmp/app-tmp", isDirectory: true)
        var events: [String] = []

        VoiceInkAppDataResetPlan.iOS(
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

    func testIOSResetFilePlanPreservesExistingDirectoryPolicy() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/recordings", isDirectory: true)
        let modelsDirectory = URL(fileURLWithPath: "/tmp/models", isDirectory: true)
        let cachesDirectory = URL(fileURLWithPath: "/tmp/caches", isDirectory: true)
        let temporaryDirectory = URL(fileURLWithPath: "/tmp/app-tmp", isDirectory: true)

        let plan = VoiceInkAppDataResetFilePlan.iOS(
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
            .appendingPathComponent("VoiceInkCore.StoredAudioFileTests.AppDataReset.\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: baseDirectory) }

        let recordingsDirectory = baseDirectory.appendingPathComponent("Recordings", isDirectory: true)
        let modelsDirectory = baseDirectory.appendingPathComponent("Models", isDirectory: true)
        let cachesDirectory = baseDirectory.appendingPathComponent("Caches", isDirectory: true)
        let temporaryDirectory = baseDirectory.appendingPathComponent("Temporary", isDirectory: true)

        for directory in [recordingsDirectory, modelsDirectory, cachesDirectory, temporaryDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("data".utf8).write(to: directory.appendingPathComponent("item.txt"))
        }

        VoiceInkAppDataResetFilePlan.iOS(
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

    func testAppDataResetDiagnosticsPreserveIOSLogCopy() {
        XCTAssertEqual(
            VoiceInkAppDataResetDiagnostics.swiftDataResetFailedMessage(errorDescription: "store unavailable"),
            "Failed to reset SwiftData: store unavailable"
        )
    }

    func testFileURLBuildsUnderRecordingsDirectory() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/VoiceInk/Recordings", isDirectory: true)

        XCTAssertEqual(
            VoiceInkStoredAudioFile.fileURL(forFilename: "recording.wav", in: recordingsDirectory).path,
            "/tmp/VoiceInk/Recordings/recording.wav"
        )
    }

    func testRecordingFileURLUsesMacOSUUIDWAVName() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/VoiceInk/Recordings", isDirectory: true)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

        XCTAssertEqual(
            VoiceInkStoredAudioFile.recordingFileURL(in: recordingsDirectory, id: id).lastPathComponent,
            "00000000-0000-0000-0000-000000000123.wav"
        )
    }

    func testTimestampedRecordingFileURLPreservesIOSName() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/VoiceInk/Recordings", isDirectory: true)
        let date = Date(timeIntervalSince1970: 1_234.9)

        XCTAssertEqual(
            VoiceInkStoredAudioFile.timestampedRecordingFileURL(in: recordingsDirectory, date: date).lastPathComponent,
            "recording_1234.wav"
        )
    }

    func testImportedTranscriptionFileURLPreservesMacOSName() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/VoiceInk/Recordings", isDirectory: true)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000456")!

        XCTAssertEqual(
            VoiceInkStoredAudioFile.importedTranscriptionFileURL(in: recordingsDirectory, id: id).lastPathComponent,
            "transcribed_00000000-0000-0000-0000-000000000456.wav"
        )
    }

    func testRetranscriptionFileURLPreservesMacOSName() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/VoiceInk/Recordings", isDirectory: true)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000789")!

        XCTAssertEqual(
            VoiceInkStoredAudioFile.retranscriptionFileURL(in: recordingsDirectory, id: id).lastPathComponent,
            "retranscribed_00000000-0000-0000-0000-000000000789.wav"
        )
    }

    func testResolvesFileURLString() {
        let fileURL = URL(fileURLWithPath: "/tmp/voiceink-recording.m4a")

        XCTAssertEqual(
            VoiceInkStoredAudioFile.resolvedURL(for: fileURL.absoluteString)?.path,
            fileURL.path
        )
    }

    func testResolvesAbsolutePath() {
        XCTAssertEqual(
            VoiceInkStoredAudioFile.resolvedURL(for: "/tmp/voiceink-recording.m4a")?.path,
            "/tmp/voiceink-recording.m4a"
        )
    }

    func testResolvesRelativeFilenameAgainstRecordingsDirectory() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/Recordings", isDirectory: true)

        XCTAssertEqual(
            VoiceInkStoredAudioFile
                .resolvedURL(for: "voiceink-recording.m4a", relativeTo: recordingsDirectory)?
                .path,
            "/tmp/Recordings/voiceink-recording.m4a"
        )
    }

    func testRejectsBlankAndRelativeValueWithoutDirectory() {
        XCTAssertNil(VoiceInkStoredAudioFile.resolvedURL(for: "  "))
        XCTAssertNil(VoiceInkStoredAudioFile.resolvedURL(for: "voiceink-recording.m4a"))
    }

    func testExistingURLReturnsNilForMissingFile() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/Recordings", isDirectory: true)

        XCTAssertNil(
            VoiceInkStoredAudioFile.existingURL(
                for: "missing-recording.m4a",
                relativeTo: recordingsDirectory
            )
        )
    }

    func testExistingURLReturnsResolvedFileWhenItExists() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.StoredAudioFileTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let recordingsDirectory = try VoiceInkStoredAudioFile.createRecordingsDirectory(in: baseDirectory)
        let fileURL = VoiceInkStoredAudioFile.fileURL(forFilename: "voiceink-recording.m4a", in: recordingsDirectory)
        try Data().write(to: fileURL)

        XCTAssertEqual(
            VoiceInkStoredAudioFile.existingURL(
                for: "voiceink-recording.m4a",
                relativeTo: recordingsDirectory
            )?.path,
            fileURL.path
        )
    }

    func testAvailabilityReturnsMissingPathForBlankOrUnresolvableStoredValue() {
        XCTAssertEqual(VoiceInkStoredAudioFile.availability(for: "  "), .missingPath)
        XCTAssertEqual(VoiceInkStoredAudioFile.availability(for: "voiceink-recording.m4a"), .missingPath)
    }

    func testAvailabilityReturnsMissingFileForResolvedMissingFile() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/Recordings", isDirectory: true)
        let expectedURL = VoiceInkStoredAudioFile.fileURL(forFilename: "missing-recording.m4a", in: recordingsDirectory)

        XCTAssertEqual(
            VoiceInkStoredAudioFile.availability(
                for: "missing-recording.m4a",
                relativeTo: recordingsDirectory
            ),
            .missingFile(expectedURL)
        )
    }

    func testAvailabilityReturnsAvailableResolvedFileWhenItExists() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.StoredAudioFileTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let recordingsDirectory = try VoiceInkStoredAudioFile.createRecordingsDirectory(in: baseDirectory)
        let fileURL = VoiceInkStoredAudioFile.fileURL(forFilename: "voiceink-recording.m4a", in: recordingsDirectory)
        try Data().write(to: fileURL)

        XCTAssertEqual(
            VoiceInkStoredAudioFile.availability(
                for: "voiceink-recording.m4a",
                relativeTo: recordingsDirectory
            ),
            .available(fileURL)
        )
    }

    func testAvailabilityPresentationKeepsExistingIOSMissingAudioText() {
        XCTAssertEqual(VoiceInkStoredAudioAvailability.available(URL(fileURLWithPath: "/tmp/a.wav")).unavailableTitle, nil)
        XCTAssertEqual(VoiceInkStoredAudioAvailability.available(URL(fileURLWithPath: "/tmp/a.wav")).unavailableDetail, nil)
        XCTAssertEqual(VoiceInkStoredAudioAvailability.unavailableSystemImageName, "exclamationmark")
        XCTAssertEqual(VoiceInkStoredAudioAvailability.missingFile(URL(fileURLWithPath: "/tmp/missing.wav")).unavailableTitle, "Audio Unavailable")
        XCTAssertEqual(VoiceInkStoredAudioAvailability.missingFile(URL(fileURLWithPath: "/tmp/missing.wav")).unavailableDetail, "File not found")
        XCTAssertEqual(VoiceInkStoredAudioAvailability.missingPath.unavailableTitle, "Audio Unavailable")
        XCTAssertEqual(VoiceInkStoredAudioAvailability.missingPath.unavailableDetail, "Path missing")
    }

    func testAvailabilityAudioSectionVisibilityPreservesMissingAudioIntent() {
        XCTAssertTrue(VoiceInkStoredAudioAvailability.available(URL(fileURLWithPath: "/tmp/a.wav")).shouldShowAudioSection(duration: 0))
        XCTAssertTrue(VoiceInkStoredAudioAvailability.missingFile(URL(fileURLWithPath: "/tmp/missing.wav")).shouldShowAudioSection(duration: 0))
        XCTAssertTrue(VoiceInkStoredAudioAvailability.missingPath.shouldShowAudioSection(duration: 1))
        XCTAssertFalse(VoiceInkStoredAudioAvailability.missingPath.shouldShowAudioSection(duration: 0))
        XCTAssertFalse(VoiceInkStoredAudioAvailability.missingPath.shouldShowAudioSection(duration: -1))
    }

    func testDeleteExistingFileRemovesResolvedFileAndReturnsURL() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.StoredAudioFileTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let recordingsDirectory = try VoiceInkStoredAudioFile.createRecordingsDirectory(in: baseDirectory)
        let fileURL = VoiceInkStoredAudioFile.fileURL(forFilename: "voiceink-recording.m4a", in: recordingsDirectory)
        try Data().write(to: fileURL)

        let deletedURL = try VoiceInkStoredAudioFile.deleteExistingFile(
            for: "voiceink-recording.m4a",
            relativeTo: recordingsDirectory
        )

        XCTAssertEqual(deletedURL?.path, fileURL.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testDeleteExistingFileReturnsNilForMissingFile() throws {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/Recordings", isDirectory: true)

        let deletedURL = try VoiceInkStoredAudioFile.deleteExistingFile(
            for: "missing-recording.m4a",
            relativeTo: recordingsDirectory
        )

        XCTAssertNil(deletedURL)
    }

    func testDeletionErrorMessagePreservesPlatformLogCopy() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.fileNoSuchFile.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "file vanished"]
        )

        XCTAssertEqual(
            VoiceInkStoredAudioFile.deletionErrorMessage(for: error),
            "Error deleting audio file: file vanished"
        )
    }

    func testStoredAudioRecordUsesDefaultRecordingsDirectory() {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/VoiceInk/Recordings", isDirectory: true)
        let record = StubStoredAudioRecord(
            audioFileURL: "voiceink-recording.m4a",
            storedAudioRecordingsDirectory: recordingsDirectory
        )

        XCTAssertEqual(
            record.resolvedAudioFileURL()?.path,
            "/tmp/VoiceInk/Recordings/voiceink-recording.m4a"
        )
    }

    func testStoredAudioRecordAllowsExplicitRecordingsDirectoryOverride() {
        let defaultDirectory = URL(fileURLWithPath: "/tmp/default/Recordings", isDirectory: true)
        let overrideDirectory = URL(fileURLWithPath: "/tmp/override/Recordings", isDirectory: true)
        let record = StubStoredAudioRecord(
            audioFileURL: "voiceink-recording.m4a",
            storedAudioRecordingsDirectory: defaultDirectory
        )

        XCTAssertEqual(
            record.resolvedAudioFileURL(relativeTo: overrideDirectory)?.path,
            "/tmp/override/Recordings/voiceink-recording.m4a"
        )
    }

    func testStoredAudioRecordDeleteUsesResolvedRecordFile() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.StoredAudioFileTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let recordingsDirectory = try VoiceInkStoredAudioFile.createRecordingsDirectory(in: baseDirectory)
        let fileURL = VoiceInkStoredAudioFile.fileURL(forFilename: "voiceink-recording.m4a", in: recordingsDirectory)
        try Data().write(to: fileURL)
        let record = StubStoredAudioRecord(
            audioFileURL: "voiceink-recording.m4a",
            storedAudioRecordingsDirectory: recordingsDirectory
        )

        XCTAssertTrue(record.hasStoredAudioFile())
        XCTAssertEqual(record.storedAudioAvailability(), .available(fileURL))
        XCTAssertEqual(try record.deleteExistingAudioFile()?.path, fileURL.path)
        XCTAssertFalse(record.hasStoredAudioFile())
    }

    func testStoredAudioRecordReportingDeleteRemovesFileWithoutReportingFailure() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.StoredAudioFileTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let recordingsDirectory = try VoiceInkStoredAudioFile.createRecordingsDirectory(in: baseDirectory)
        let fileURL = VoiceInkStoredAudioFile.fileURL(forFilename: "voiceink-recording.m4a", in: recordingsDirectory)
        try Data().write(to: fileURL)
        let record = StubStoredAudioRecord(
            audioFileURL: "voiceink-recording.m4a",
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
            .appendingPathComponent("VoiceInkCore.StoredAudioFileTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let recordingsDirectory = try VoiceInkStoredAudioFile.createRecordingsDirectory(in: baseDirectory)
        let fileURL = VoiceInkStoredAudioFile.fileURL(forFilename: "voiceink-recording.m4a", in: recordingsDirectory)
        try Data().write(to: fileURL)
        let record = StubStoredAudioRecord(
            audioFileURL: "voiceink-recording.m4a",
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
            .appendingPathComponent("VoiceInkCore.StoredAudioFileTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let recordingsDirectory = try VoiceInkStoredAudioFile.createRecordingsDirectory(in: baseDirectory)
        let fileURL = VoiceInkStoredAudioFile.fileURL(forFilename: "voiceink-recording.m4a", in: recordingsDirectory)
        try Data().write(to: fileURL)
        let record = StubStoredAudioRecord(
            audioFileURL: "voiceink-recording.m4a",
            storedAudioRecordingsDirectory: recordingsDirectory
        )

        XCTAssertEqual(try record.deleteExistingAudioFileAndClearReference()?.path, fileURL.path)
        XCTAssertNil(record.audioFileURL)
        XCTAssertNil(try record.deleteExistingAudioFileAndClearReference())

        record.audioFileURL = "missing-recording.m4a"
        XCTAssertNil(try record.deleteExistingAudioFileAndClearReference())
        XCTAssertEqual(record.audioFileURL, "missing-recording.m4a")
    }

    func testSupportedMediaDisplayExtensionsPreserveMacOSImportCopyOrder() {
        XCTAssertEqual(
            VoiceInkSupportedMedia.displayFileExtensions,
            [
                "WAV", "MP3", "M4A", "AIFF", "MP4", "MOV", "AAC", "FLAC", "CAF",
                "AMR", "OGG", "OGA", "OPUS", "3GP"
            ]
        )
        XCTAssertEqual(
            VoiceInkSupportedMedia.supportedFileTypesText,
            "Supports WAV, MP3, M4A, AIFF, MP4, MOV, AAC, FLAC, CAF, AMR, OGG, OGA, OPUS, 3GP"
        )
    }

    func testSupportedMediaImportTypePoliciesPreserveMacOSShellIdentifiers() {
        XCTAssertEqual(
            VoiceInkSupportedMedia.contentTypes.map { $0.identifier },
            [UTType.audio.identifier, UTType.movie.identifier]
        )
        XCTAssertEqual(
            VoiceInkSupportedMedia.openPanelContentTypes.map { $0.identifier },
            VoiceInkSupportedMedia.contentTypes.map { $0.identifier }
        )
        XCTAssertEqual(
            VoiceInkSupportedMedia.dropContentTypes.map { $0.identifier },
            [
                UTType.fileURL.identifier,
                UTType.data.identifier,
                UTType.audio.identifier,
                UTType.movie.identifier
            ]
        )
        XCTAssertEqual(VoiceInkSupportedMedia.legacyDropFileURLTypeIdentifier, "public.file-url")
        XCTAssertEqual(
            VoiceInkSupportedMedia.dropProviderTypeIdentifiers,
            [
                UTType.fileURL.identifier,
                UTType.audio.identifier,
                UTType.movie.identifier,
                UTType.data.identifier,
                "public.file-url"
            ]
        )
    }

    func testAudioImportPresentationPreservesMacOSQueueCopyAndActions() {
        XCTAssertEqual(VoiceInkAudioImportPresentation.dropTargetSystemImageName, "arrow.down.doc")
        XCTAssertEqual(VoiceInkAudioImportPresentation.dropTargetTitle, "Drop audio or video files here")
        XCTAssertEqual(VoiceInkAudioImportPresentation.dropTargetDividerText, "or")
        XCTAssertEqual(VoiceInkAudioImportPresentation.chooseFilesButtonTitle, "Choose Files")
        XCTAssertEqual(VoiceInkAudioImportPresentation.dropMoreHintText, "Drop files anywhere to add more")
        XCTAssertEqual(VoiceInkAudioImportPresentation.dropOverlayText, "Drop to add files")
        XCTAssertEqual(VoiceInkAudioImportPresentation.queueCountText(1), "1 file")
        XCTAssertEqual(VoiceInkAudioImportPresentation.queueCountText(2), "2 files")
        XCTAssertEqual(VoiceInkAudioImportPresentation.addButtonSystemImageName, "plus")
        XCTAssertEqual(VoiceInkAudioImportPresentation.addButtonTitle, "Add")
        XCTAssertEqual(VoiceInkAudioImportPresentation.addButtonHelpText, "Add files")
        XCTAssertEqual(VoiceInkAudioImportPresentation.cancelButtonSystemImageName, "stop.fill")
        XCTAssertEqual(VoiceInkAudioImportPresentation.cancelButtonTitle, "Cancel")
        XCTAssertEqual(VoiceInkAudioImportPresentation.cancelButtonHelpText, "Cancel transcription")
        XCTAssertEqual(VoiceInkAudioImportPresentation.startButtonSystemImageName, "play.fill")
        XCTAssertEqual(VoiceInkAudioImportPresentation.startButtonTitle, "Start")
        XCTAssertEqual(VoiceInkAudioImportPresentation.clearButtonSystemImageName, "xmark.bin")
        XCTAssertEqual(VoiceInkAudioImportPresentation.clearButtonTitle, "Clear")
        XCTAssertEqual(VoiceInkAudioImportPresentation.clearButtonHelpText, "Clear all items")
        XCTAssertEqual(VoiceInkAudioImportPresentation.enhancementToggleTitle, "AI Enhancement")
        XCTAssertEqual(VoiceInkAudioImportPresentation.promptPickerTitle, "Prompt")
        XCTAssertEqual(
            VoiceInkAudioImportPresentation.droppedFileLoadFailedDiagnosticMessage(errorDescription: "provider error"),
            "Error loading dropped file: provider error"
        )
    }

    func testAudioFileQueueProcessingPhasesPreserveCopy() {
        XCTAssertEqual(VoiceInkAudioFileQueueProcessingPhase.loading.displayText, "Loading model...")
        XCTAssertEqual(VoiceInkAudioFileQueueProcessingPhase.processingAudio.displayText, "Processing audio...")
        XCTAssertEqual(VoiceInkAudioFileQueueProcessingPhase.transcribing.displayText, "Transcribing...")
        XCTAssertEqual(VoiceInkAudioFileQueueProcessingPhase.enhancing.displayText, "Enhancing...")
    }

    func testAudioFileQueueStatusCancelingProcessingResetsOnlyProcessingItems() {
        XCTAssertEqual(
            VoiceInkAudioFileQueueStatus.processing(phase: .transcribing).statusAfterCancelingProcessing,
            .pending
        )
        XCTAssertEqual(VoiceInkAudioFileQueueStatus.pending.statusAfterCancelingProcessing, .pending)
        XCTAssertEqual(VoiceInkAudioFileQueueStatus.completed.statusAfterCancelingProcessing, .completed)
        XCTAssertEqual(
            VoiceInkAudioFileQueueStatus.failed(message: "No model").statusAfterCancelingProcessing,
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
            VoiceInkAudioFileQueueItemFacts(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                standardizedPath: activeURL.standardizedFileURL.path,
                status: .pending
            ),
            VoiceInkAudioFileQueueItemFacts(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                standardizedPath: completedURL.standardizedFileURL.path,
                status: .completed
            ),
            VoiceInkAudioFileQueueItemFacts(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                standardizedPath: failedURL.standardizedFileURL.path,
                status: .failed(message: "No model")
            ),
            VoiceInkAudioFileQueueItemFacts(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                standardizedPath: processingURL.standardizedFileURL.path,
                status: .processing(phase: .transcribing)
            )
        ]

        let additions = VoiceInkAudioFileQueuePolicy.eligibleAdditionURLs(
            from: [
                VoiceInkAudioFileQueueCandidate(url: activeURL, fileExists: true, isSupported: true),
                VoiceInkAudioFileQueueCandidate(url: completedURL, fileExists: true, isSupported: true),
                VoiceInkAudioFileQueueCandidate(url: failedURL, fileExists: true, isSupported: true),
                VoiceInkAudioFileQueueCandidate(url: processingURL, fileExists: true, isSupported: true),
                VoiceInkAudioFileQueueCandidate(url: unsupportedURL, fileExists: true, isSupported: false),
                VoiceInkAudioFileQueueCandidate(url: missingURL, fileExists: false, isSupported: true),
                VoiceInkAudioFileQueueCandidate(url: freshURL, fileExists: true, isSupported: true)
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
            VoiceInkAudioFileQueueItemFacts(
                id: processingId,
                standardizedPath: "/tmp/processing.wav",
                status: .processing(phase: .loading)
            ),
            VoiceInkAudioFileQueueItemFacts(
                id: pendingId,
                standardizedPath: "/tmp/pending.wav",
                status: .pending
            ),
            VoiceInkAudioFileQueueItemFacts(
                id: failedId,
                standardizedPath: "/tmp/failed.wav",
                status: .failed(message: "No model")
            )
        ]

        XCTAssertTrue(VoiceInkAudioFileQueuePolicy.canRemoveItem(id: pendingId, from: items))
        XCTAssertFalse(VoiceInkAudioFileQueuePolicy.canRemoveItem(id: failedId, from: items))
        XCTAssertFalse(VoiceInkAudioFileQueuePolicy.canRemoveItem(id: missingId, from: items))
        XCTAssertEqual(VoiceInkAudioFileQueuePolicy.statusAfterRetryRequest(.failed(message: "No model")), .pending)
        XCTAssertNil(VoiceInkAudioFileQueuePolicy.statusAfterRetryRequest(.completed))
        XCTAssertEqual(VoiceInkAudioFileQueuePolicy.nextPendingItemID(in: items), pendingId)
        XCTAssertTrue(VoiceInkAudioFileQueuePolicy.hasPendingItems(in: items))
        XCTAssertEqual(
            VoiceInkAudioFileQueuePolicy.statusesAfterCancelingProcessing(items.map(\.status)),
            [.pending, .pending, .failed(message: "No model")]
        )
    }

    func testAudioFileQueueDiagnosticsPreserveMacOSLogCopy() {
        XCTAssertEqual(
            VoiceInkAudioFileQueueDiagnostics.enhancementFailedMessage(errorDescription: "timeout"),
            "Enhancement failed: timeout"
        )
        XCTAssertEqual(
            VoiceInkAudioFileQueueDiagnostics.transcriptionErrorMessage(errorDescription: "No model"),
            "Transcription error: No model"
        )
    }

    func testAudioFileQueuePresentationPreservesRowCopyAndIcons() {
        XCTAssertEqual(VoiceInkAudioFileQueuePresentation.pendingStatusSystemImageName, "clock")
        XCTAssertEqual(VoiceInkAudioFileQueuePresentation.pendingStatusText, "Waiting")
        XCTAssertEqual(VoiceInkAudioFileQueuePresentation.removeButtonSystemImageName, "xmark.circle.fill")
        XCTAssertEqual(VoiceInkAudioFileQueuePresentation.completedStatusSystemImageName, "checkmark.circle.fill")
        XCTAssertEqual(VoiceInkAudioFileQueuePresentation.expandSystemImageName, "chevron.right")
        XCTAssertEqual(VoiceInkAudioFileQueuePresentation.transcriptionModelSystemImageName, "cpu")
        XCTAssertEqual(VoiceInkAudioFileQueuePresentation.promptSystemImageName, "sparkles")
        XCTAssertEqual(VoiceInkAudioFileQueuePresentation.failedStatusSystemImageName, "exclamationmark.circle.fill")
        XCTAssertEqual(VoiceInkAudioFileQueuePresentation.retryButtonSystemImageName, "arrow.counterclockwise")
    }

    func testSupportedFileExtensionsPreserveMacOSImportPolicy() {
        XCTAssertEqual(
            VoiceInkSupportedMedia.fileExtensions,
            [
                "wav", "mp3", "m4a", "aiff", "mp4", "mov", "aac", "flac", "caf",
                "amr", "ogg", "oga", "opus", "3gp"
            ]
        )
    }

    func testSupportedMediaDisplayExtensionsMatchAcceptedExtensions() {
        XCTAssertEqual(
            Set(VoiceInkSupportedMedia.displayFileExtensions.map { $0.lowercased() }),
            VoiceInkSupportedMedia.fileExtensions
        )
    }

    func testSupportedFileExtensionLookupIsCaseInsensitive() {
        XCTAssertTrue(VoiceInkSupportedMedia.isSupportedFileExtension("WAV"))
        XCTAssertTrue(VoiceInkSupportedMedia.isSupportedFileExtension("m4a"))
        XCTAssertFalse(VoiceInkSupportedMedia.isSupportedFileExtension("txt"))
    }

    func testSupportedURLAcceptsKnownExtensions() {
        XCTAssertTrue(
            VoiceInkSupportedMedia.isSupported(
                url: URL(fileURLWithPath: "/tmp/recording.MOV")
            )
        )
    }

    func testSupportedURLRejectsUnknownExtensionWithoutContentType() {
        XCTAssertFalse(
            VoiceInkSupportedMedia.isSupported(
                url: URL(fileURLWithPath: "/tmp/recording.voiceink-unknown")
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

private final class StubStoredAudioRecord: VoiceInkStoredAudioRecord {
    var audioFileURL: String?
    let storedAudioRecordingsDirectory: URL?

    init(audioFileURL: String?, storedAudioRecordingsDirectory: URL?) {
        self.audioFileURL = audioFileURL
        self.storedAudioRecordingsDirectory = storedAudioRecordingsDirectory
    }
}
