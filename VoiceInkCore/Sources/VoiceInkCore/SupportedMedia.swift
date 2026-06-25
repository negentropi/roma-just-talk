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
    public static let openPanelContentTypes = contentTypes
    public static let dropContentTypes: [UTType] = [
        .fileURL, .data, .audio, .movie
    ]
    public static let legacyDropFileURLTypeIdentifier = "public.file-url"
    public static let dropProviderTypeIdentifiers = [
        UTType.fileURL.identifier,
        UTType.audio.identifier,
        UTType.movie.identifier,
        UTType.data.identifier,
        legacyDropFileURLTypeIdentifier
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

    public var statusAfterCancelingProcessing: Self {
        switch self {
        case .processing:
            return .pending
        case .pending, .completed, .failed:
            return self
        }
    }
}

public struct VoiceInkAudioFileQueueCandidate: Equatable, Sendable {
    public let url: URL
    public let fileExists: Bool
    public let isSupported: Bool

    public init(url: URL, fileExists: Bool, isSupported: Bool) {
        self.url = url
        self.fileExists = fileExists
        self.isSupported = isSupported
    }

    var standardizedPath: String {
        url.standardizedFileURL.path
    }
}

public struct VoiceInkAudioFileQueueItemFacts<ID: Hashable & Sendable>: Equatable, Sendable {
    public let id: ID
    public let standardizedPath: String
    public let status: VoiceInkAudioFileQueueStatus

    public init(id: ID, standardizedPath: String, status: VoiceInkAudioFileQueueStatus) {
        self.id = id
        self.standardizedPath = standardizedPath
        self.status = status
    }
}

public enum VoiceInkAudioFileQueuePolicy {
    public static func eligibleAdditionURLs<ID: Hashable & Sendable>(
        from candidates: [VoiceInkAudioFileQueueCandidate],
        existingItems: [VoiceInkAudioFileQueueItemFacts<ID>]
    ) -> [URL] {
        let activePaths = Set(existingItems.filter { item in
            switch item.status {
            case .pending, .processing:
                return true
            case .completed, .failed:
                return false
            }
        }.map(\.standardizedPath))

        return candidates.compactMap { candidate in
            guard candidate.fileExists, candidate.isSupported else { return nil }
            guard !activePaths.contains(candidate.standardizedPath) else { return nil }
            return candidate.url
        }
    }

    public static func canRemoveItem<ID: Hashable & Sendable>(
        id: ID,
        from items: [VoiceInkAudioFileQueueItemFacts<ID>]
    ) -> Bool {
        guard let status = items.first(where: { $0.id == id })?.status else {
            return false
        }
        switch status {
        case .pending:
            return true
        case .processing, .completed, .failed:
            return false
        }
    }

    public static func statusAfterRetryRequest(_ status: VoiceInkAudioFileQueueStatus) -> VoiceInkAudioFileQueueStatus? {
        switch status {
        case .failed:
            return .pending
        case .pending, .processing, .completed:
            return nil
        }
    }

    public static func nextPendingItemID<ID: Hashable & Sendable>(
        in items: [VoiceInkAudioFileQueueItemFacts<ID>]
    ) -> ID? {
        items.first { item in
            switch item.status {
            case .pending:
                return true
            case .processing, .completed, .failed:
                return false
            }
        }?.id
    }

    public static func hasPendingItems<ID: Hashable & Sendable>(
        in items: [VoiceInkAudioFileQueueItemFacts<ID>]
    ) -> Bool {
        nextPendingItemID(in: items) != nil
    }

    public static func statusesAfterCancelingProcessing(
        _ statuses: [VoiceInkAudioFileQueueStatus]
    ) -> [VoiceInkAudioFileQueueStatus] {
        statuses.map(\.statusAfterCancelingProcessing)
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

    public static func droppedFileLoadFailedDiagnosticMessage(errorDescription: String) -> String {
        "Error loading dropped file: \(errorDescription)"
    }

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
