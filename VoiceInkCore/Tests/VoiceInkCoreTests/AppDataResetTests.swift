import Foundation
@testable import VoiceInkCore

final class AppDataResetTests: XCTestCase {
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
            .appendingPathComponent("VoiceInkCore.AppDataResetTests.\(UUID().uuidString)", isDirectory: true)
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
}
