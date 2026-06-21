import Foundation
import UniformTypeIdentifiers

public enum VoiceInkSupportedMedia {
    public static let displayFileExtensions = [
        "WAV", "MP3", "M4A", "AIFF", "MP4", "MOV", "AAC", "FLAC", "CAF",
        "AMR", "OGG", "OGA", "OPUS", "3GP"
    ]

    public static let fileExtensions = Set(displayFileExtensions.map { $0.lowercased() })
    public static let supportedFileTypesText = "Supports \(displayFileExtensions.joined(separator: ", "))"

    public static let contentTypes: [UTType] = [
        .audio, .movie
    ]

    public static func isSupportedFileExtension(_ fileExtension: String) -> Bool {
        fileExtensions.contains(fileExtension.lowercased())
    }

    public static func isSupported(url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        if !fileExtension.isEmpty, isSupportedFileExtension(fileExtension) {
            return true
        }

        if let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
           let contentType = resourceValues.contentType {
            return contentTypes.contains(where: { contentType.conforms(to: $0) })
        }

        return false
    }
}

public enum VoiceInkAudioFileQueueProcessingPhase: String, Equatable, Sendable {
    case loading = "Loading model..."
    case processingAudio = "Processing audio..."
    case transcribing = "Transcribing..."
    case enhancing = "Enhancing..."

    public var displayText: String {
        rawValue
    }
}

public enum VoiceInkAudioFileQueueStatus: Equatable, Sendable {
    case pending
    case processing(phase: VoiceInkAudioFileQueueProcessingPhase)
    case completed
    case failed(message: String)

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed:
            return true
        case .pending, .processing:
            return false
        }
    }
}

public enum VoiceInkAudioImportPresentation {
    public static let dropTargetSystemImageName = "arrow.down.doc"
    public static let dropTargetTitle = "Drop audio or video files here"
    public static let dropTargetDividerText = "or"
    public static let chooseFilesButtonTitle = "Choose Files"
    public static let dropMoreHintText = "Drop files anywhere to add more"
    public static let dropOverlayText = "Drop to add files"
    public static let addButtonSystemImageName = "plus"
    public static let addButtonTitle = "Add"
    public static let addButtonHelpText = "Add files"
    public static let cancelButtonSystemImageName = "stop.fill"
    public static let cancelButtonTitle = "Cancel"
    public static let cancelButtonHelpText = "Cancel transcription"
    public static let startButtonSystemImageName = "play.fill"
    public static let startButtonTitle = "Start"
    public static let clearButtonSystemImageName = "xmark.bin"
    public static let clearButtonTitle = "Clear"
    public static let clearButtonHelpText = "Clear all items"
    public static let enhancementToggleTitle = "AI Enhancement"
    public static let promptPickerTitle = "Prompt"

    public static func queueCountText(_ count: Int) -> String {
        "\(count) file\(count == 1 ? "" : "s")"
    }
}

public enum VoiceInkAudioFileQueuePresentation {
    public static let pendingStatusSystemImageName = "clock"
    public static let pendingStatusText = "Waiting"
    public static let removeButtonSystemImageName = "xmark.circle.fill"
    public static let completedStatusSystemImageName = "checkmark.circle.fill"
    public static let expandSystemImageName = "chevron.right"
    public static let transcriptionModelSystemImageName = "cpu"
    public static let promptSystemImageName = "sparkles"
    public static let failedStatusSystemImageName = "exclamationmark.circle.fill"
    public static let retryButtonSystemImageName = "arrow.counterclockwise"
}
