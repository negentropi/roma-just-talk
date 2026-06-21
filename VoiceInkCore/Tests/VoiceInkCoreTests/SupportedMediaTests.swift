import Foundation
import UniformTypeIdentifiers
import VoiceInkCore

final class SupportedMediaTests: XCTestCase {
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
    }

    func testAudioFileQueueStatusPreservesTerminalAndProcessingPolicies() {
        XCTAssertFalse(VoiceInkAudioFileQueueStatus.pending.isTerminal)
        XCTAssertFalse(VoiceInkAudioFileQueueStatus.processing(phase: .loading).isTerminal)
        XCTAssertTrue(VoiceInkAudioFileQueueStatus.completed.isTerminal)
        XCTAssertTrue(VoiceInkAudioFileQueueStatus.failed(message: "No model").isTerminal)
        XCTAssertTrue(VoiceInkAudioFileQueueStatus.pending.isPending)
        XCTAssertFalse(VoiceInkAudioFileQueueStatus.completed.isPending)
        XCTAssertTrue(VoiceInkAudioFileQueueStatus.processing(phase: .transcribing).isProcessing)
        XCTAssertFalse(VoiceInkAudioFileQueueStatus.failed(message: "No model").isProcessing)
        XCTAssertEqual(VoiceInkAudioFileQueueProcessingPhase.loading.displayText, "Loading model...")
        XCTAssertEqual(VoiceInkAudioFileQueueProcessingPhase.processingAudio.displayText, "Processing audio...")
        XCTAssertEqual(VoiceInkAudioFileQueueProcessingPhase.transcribing.displayText, "Transcribing...")
        XCTAssertEqual(VoiceInkAudioFileQueueProcessingPhase.enhancing.displayText, "Enhancing...")
    }

    func testAudioFileQueueStatusPreservesMutationPredicates() {
        XCTAssertTrue(VoiceInkAudioFileQueueStatus.pending.canRemoveFromQueue)
        XCTAssertFalse(VoiceInkAudioFileQueueStatus.processing(phase: .loading).canRemoveFromQueue)
        XCTAssertFalse(VoiceInkAudioFileQueueStatus.completed.canRemoveFromQueue)
        XCTAssertFalse(VoiceInkAudioFileQueueStatus.failed(message: "No model").canRemoveFromQueue)

        XCTAssertFalse(VoiceInkAudioFileQueueStatus.pending.canRetry)
        XCTAssertFalse(VoiceInkAudioFileQueueStatus.processing(phase: .loading).canRetry)
        XCTAssertFalse(VoiceInkAudioFileQueueStatus.completed.canRetry)
        XCTAssertTrue(VoiceInkAudioFileQueueStatus.failed(message: "No model").canRetry)
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
