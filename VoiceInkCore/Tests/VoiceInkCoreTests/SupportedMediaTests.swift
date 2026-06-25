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
