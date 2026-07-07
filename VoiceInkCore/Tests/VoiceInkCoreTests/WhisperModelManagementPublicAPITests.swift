import Foundation
import VoiceInkCore

final class WhisperModelManagementPublicAPITests: XCTestCase {
    func testMovedWhisperModelManagementSymbolsExposePublicAPI() {
        let model = VoiceInkWhisperModelFiles.baseModel
        let modelsDirectory = URL(fileURLWithPath: "/tmp/VoiceInk/WhisperModels", isDirectory: true)

        let progress = VoiceInkWhisperModelDownloadProgress.simple(
            modelName: model.modelName,
            isDownloading: true,
            progress: 0.42
        )
        XCTAssertTrue(progress.isActive)
        XCTAssertEqual(progress.compactStatusText, "Downloading...")
        XCTAssertEqual(progress.percentText, "42%")

        let state = VoiceInkWhisperModelDownloadState(isDownloaded: false, progress: progress)
        let row = state.rowPresentation(for: model)
        XCTAssertEqual(row.downloadButtonTitle, "Download Model (142 MB)")
        XCTAssertTrue(row.shouldShowCircularProgressAccessory)

        let managementRow = VoiceInkWhisperModelManagementList.row(
            for: model,
            downloadState: state
        )
        XCTAssertNil(managementRow.confirmedDownloadRuntimeAction {})
        XCTAssertEqual(managementRow.downloadConfirmation.primaryButtonTitle, "Download")
        XCTAssertEqual(managementRow.deleteConfirmation.primaryButtonTitle, "Delete")

        let completionPlan = VoiceInkWhisperModelSimpleDownloadCompletionPlan.completion(
            temporaryURL: nil,
            response: nil,
            error: nil
        )
        var failureID = ""
        completionPlan.applyRuntimeState(
            installTemporaryFile: { _ in XCTFail("missing file should not install") },
            presentFailure: { failureID = $0.id },
            ignoreCancellation: { XCTFail("missing file should not cancel") }
        )
        XCTAssertEqual(failureID, "serverErrorDuringDownload")

        var trackingState = VoiceInkWhisperModelSimpleDownloadTrackingState()
        XCTAssertTrue(trackingState.startDownload(for: model))
        trackingState.updateProgress(0.5, for: model)

        var sessionState = VoiceInkWhisperModelSimpleDownloadSessionState(
            downloadTrackingState: trackingState
        )
        XCTAssertNil(sessionState.startDownload(for: model))
        XCTAssertTrue(sessionState.isDownloading(model))

        let snapshot = VoiceInkWhisperModelManagementSnapshot(
            modelsDirectory: modelsDirectory,
            downloadTrackingState: trackingState
        )
        XCTAssertFalse(snapshot.hasAvailableModel())
        XCTAssertNil(snapshot.modelPath(forRuntimeModelName: model.modelName))
        XCTAssertEqual(snapshot.managementRows().count, VoiceInkWhisperModelFiles.bootstrapModels.count)

        let deletionPlan = VoiceInkWhisperModelDeletionPolicy.plan(isDownloaded: false)
        var skippedMissingFile = false
        deletionPlan.applyRuntimeState(
            skipMissingFile: { skippedMissingFile = true },
            deleteDownloadedFiles: { XCTFail("missing file should not delete") },
            refreshAfterSuccessfulDelete: { XCTFail("missing file should not refresh") },
            handleDeleteFailure: { _ in XCTFail("missing file should not fail") }
        )
        XCTAssertTrue(skippedMissingFile)

        XCTAssertEqual(
            VoiceInkWhisperModelOperationConfirmationPresentation.download(for: model).title,
            "Download Model"
        )
        XCTAssertEqual(
            VoiceInkWhisperModelOperationAlertPresentation.noFileReceived.message,
            "No file received"
        )
        XCTAssertEqual(
            VoiceInkWhisperModelManagementDiagnostics.alreadyDownloadingMessage(modelName: model.modelName),
            "Model \(model.modelName) is already being downloaded."
        )
    }
}
