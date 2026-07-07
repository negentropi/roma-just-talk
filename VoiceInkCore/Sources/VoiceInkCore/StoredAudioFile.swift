import Foundation
import UniformTypeIdentifiers

public enum VoiceInkStoredAudioAvailability: Equatable, Sendable {
    case available(URL)
    case missingFile(URL)
    case missingPath

    public static let unavailableSystemImageName = "exclamationmark"

    public var existingURL: URL? {
        guard case let .available(url) = self else {
            return nil
        }
        return url
    }

    public func shouldShowAudioSection(duration: TimeInterval) -> Bool {
        switch self {
        case .available, .missingFile:
            return true
        case .missingPath:
            return VoiceInkDurationPresentation.shouldShowPositiveDuration(duration)
        }
    }

    public var unavailableTitle: String? {
        switch self {
        case .available:
            return nil
        case .missingFile, .missingPath:
            return "Audio Unavailable"
        }
    }

    public var unavailableDetail: String? {
        switch self {
        case .available:
            return nil
        case .missingFile:
            return "File not found"
        case .missingPath:
            return "Path missing"
        }
    }
}

public enum VoiceInkStoredAudioFile {
    public static let recordingsDirectoryName = "Recordings"

    public static func recordingsDirectory(in baseDirectory: URL) -> URL {
        baseDirectory.appendingPathComponent(recordingsDirectoryName, isDirectory: true)
    }

    public static func createRecordingsDirectory(
        in baseDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let directory = recordingsDirectory(in: baseDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func fileURL(forFilename filename: String, in recordingsDirectory: URL) -> URL {
        recordingsDirectory.appendingPathComponent(filename)
    }

    public static func recordingFileURL(
        in recordingsDirectory: URL,
        id: UUID = UUID()
    ) -> URL {
        fileURL(forFilename: "\(id.uuidString).wav", in: recordingsDirectory)
    }

    public static func timestampedRecordingFileURL(
        in recordingsDirectory: URL,
        date: Date = Date()
    ) -> URL {
        fileURL(
            forFilename: "recording_\(Int(date.timeIntervalSince1970)).wav",
            in: recordingsDirectory
        )
    }

    public static func importedTranscriptionFileURL(
        in recordingsDirectory: URL,
        id: UUID = UUID()
    ) -> URL {
        fileURL(forFilename: "transcribed_\(id.uuidString).wav", in: recordingsDirectory)
    }

    public static func retranscriptionFileURL(
        in recordingsDirectory: URL,
        id: UUID = UUID()
    ) -> URL {
        fileURL(forFilename: "retranscribed_\(id.uuidString).wav", in: recordingsDirectory)
    }

    public static func resolvedURL(
        for storedValue: String?,
        relativeTo recordingsDirectory: URL? = nil
    ) -> URL? {
        guard let storedValue = cleanedStoredValue(storedValue) else {
            return nil
        }

        if let url = URL(string: storedValue),
           let scheme = url.scheme,
           !scheme.isEmpty {
            return url
        }

        if storedValue.hasPrefix("/") {
            return URL(fileURLWithPath: storedValue)
        }

        guard let recordingsDirectory else {
            return nil
        }
        return fileURL(forFilename: storedValue, in: recordingsDirectory)
    }

    public static func resolvedPath(
        for storedValue: String?,
        relativeTo recordingsDirectory: URL? = nil
    ) -> String? {
        resolvedURL(for: storedValue, relativeTo: recordingsDirectory)?.path
    }

    public static func existingURL(
        for storedValue: String?,
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let url = resolvedURL(for: storedValue, relativeTo: recordingsDirectory),
              fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    public static func availability(
        for storedValue: String?,
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> VoiceInkStoredAudioAvailability {
        guard let url = resolvedURL(for: storedValue, relativeTo: recordingsDirectory) else {
            return .missingPath
        }

        return fileManager.fileExists(atPath: url.path)
            ? .available(url)
            : .missingFile(url)
    }

    public static func fileExists(
        for storedValue: String?,
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        existingURL(for: storedValue, relativeTo: recordingsDirectory, fileManager: fileManager) != nil
    }

    public static func deletionErrorMessage(for error: Error) -> String {
        "Error deleting audio file: \(error.localizedDescription)"
    }

    @discardableResult
    public static func deleteExistingFile(
        for storedValue: String?,
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL? {
        guard let url = existingURL(
            for: storedValue,
            relativeTo: recordingsDirectory,
            fileManager: fileManager
        ) else {
            return nil
        }

        try fileManager.removeItem(at: url)
        return url
    }

    @discardableResult
    public static func deleteExistingFileReportingFailure(
        for storedValue: String?,
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default,
        reportFailure: (String) -> Void
    ) -> URL? {
        do {
            return try deleteExistingFile(
                for: storedValue,
                relativeTo: recordingsDirectory,
                fileManager: fileManager
            )
        } catch {
            reportFailure(deletionErrorMessage(for: error))
            return nil
        }
    }

    private static func cleanedStoredValue(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

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

public enum VoiceInkAudioFileQueueDiagnostics {
    public static func enhancementFailedMessage(errorDescription: String) -> String {
        "Enhancement failed: \(errorDescription)"
    }

    public static func transcriptionErrorMessage(errorDescription: String) -> String {
        "Transcription error: \(errorDescription)"
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

public enum VoiceInkIOSStorageDirectories {
    public static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    public static func recordingsDirectory(in documentsDirectory: URL) -> URL {
        VoiceInkStoredAudioFile.recordingsDirectory(in: documentsDirectory)
    }

    public static var recordingsDirectory: URL {
        recordingsDirectory(in: documentsDirectory)
    }

    public static func preparedRecordingsDirectory(
        in documentsDirectory: URL,
        fileManager: FileManager = .default
    ) -> URL {
        (try? VoiceInkStoredAudioFile.createRecordingsDirectory(
            in: documentsDirectory,
            fileManager: fileManager
        )) ?? recordingsDirectory(in: documentsDirectory)
    }

    public static var preparedRecordingsDirectory: URL {
        preparedRecordingsDirectory(in: documentsDirectory)
    }

    public static func modelsDirectory(in documentsDirectory: URL) -> URL {
        VoiceInkWhisperModelFiles.modelsDirectory(in: documentsDirectory)
    }

    public static var modelsDirectory: URL {
        modelsDirectory(in: documentsDirectory)
    }

    public static func preparedModelsDirectory(
        in documentsDirectory: URL,
        fileManager: FileManager = .default
    ) -> URL {
        (try? VoiceInkWhisperModelFiles.createModelsDirectory(
            in: documentsDirectory,
            fileManager: fileManager
        )) ?? modelsDirectory(in: documentsDirectory)
    }

    public static var preparedModelsDirectory: URL {
        preparedModelsDirectory(in: documentsDirectory)
    }

    public static var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    public static var temporaryDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }
}

public enum VoiceInkMacOSStorageDirectories {
    public static var applicationSupportBaseDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    public static func appSupportDirectory(in applicationSupportBaseDirectory: URL) -> URL {
        VoiceInkAppIdentity.macOSApplicationSupportDirectory(in: applicationSupportBaseDirectory)
    }

    public static var appSupportDirectory: URL {
        appSupportDirectory(in: applicationSupportBaseDirectory)
    }

    public static func recordingsDirectory(in appSupportDirectory: URL) -> URL {
        VoiceInkStoredAudioFile.recordingsDirectory(in: appSupportDirectory)
    }

    public static var recordingsDirectory: URL {
        recordingsDirectory(in: appSupportDirectory)
    }

    public static func modelsDirectory(in appSupportDirectory: URL) -> URL {
        VoiceInkWhisperModelFiles.modelsDirectory(in: appSupportDirectory)
    }

    public static var modelsDirectory: URL {
        modelsDirectory(in: appSupportDirectory)
    }

    public static func customSoundsDirectory(in applicationSupportBaseDirectory: URL) -> URL {
        applicationSupportBaseDirectory.appendingPathComponent(
            VoiceInkCustomSoundPreference.customSoundsRelativeDirectory,
            isDirectory: true
        )
    }

    public static var customSoundsDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            .map { customSoundsDirectory(in: $0) }
    }
}

public enum VoiceInkAppDataResetStep: Equatable, Sendable {
    case deleteTranscriptionRecords
    case cleanFiles(VoiceInkAppDataResetFilePlan)
    case resetAppSettings
}

public struct VoiceInkAppDataResetPlan: Equatable, Sendable {
    public let steps: [VoiceInkAppDataResetStep]

    public init(steps: [VoiceInkAppDataResetStep]) {
        self.steps = steps
    }

    public static func iOS(
        recordingsDirectory: URL,
        modelsDirectory: URL,
        cachesDirectory: URL,
        temporaryDirectory: URL
    ) -> Self {
        Self(steps: [
            .deleteTranscriptionRecords,
            .cleanFiles(VoiceInkAppDataResetFilePlan.iOS(
                recordingsDirectory: recordingsDirectory,
                modelsDirectory: modelsDirectory,
                cachesDirectory: cachesDirectory,
                temporaryDirectory: temporaryDirectory
            )),
            .resetAppSettings
        ])
    }

    public static func iOS() -> Self {
        iOS(
            recordingsDirectory: VoiceInkIOSStorageDirectories.recordingsDirectory,
            modelsDirectory: VoiceInkIOSStorageDirectories.modelsDirectory,
            cachesDirectory: VoiceInkIOSStorageDirectories.cachesDirectory,
            temporaryDirectory: VoiceInkIOSStorageDirectories.temporaryDirectory
        )
    }
}

public extension VoiceInkAppDataResetPlan {
    func applyRuntimeState(
        deleteTranscriptionRecords: () -> Void,
        cleanFiles: (VoiceInkAppDataResetFilePlan) -> Void = { $0.performBestEffort() },
        resetAppSettings: () -> Void
    ) {
        for step in steps {
            switch step {
            case .deleteTranscriptionRecords:
                deleteTranscriptionRecords()
            case .cleanFiles(let filePlan):
                cleanFiles(filePlan)
            case .resetAppSettings:
                resetAppSettings()
            }
        }
    }
}

public struct VoiceInkAppDataResetFilePlan: Equatable, Sendable {
    public let directoriesToRemove: [URL]
    public let directoriesToEmpty: [URL]

    public init(
        directoriesToRemove: [URL] = [],
        directoriesToEmpty: [URL] = []
    ) {
        self.directoriesToRemove = directoriesToRemove
        self.directoriesToEmpty = directoriesToEmpty
    }

    public static func iOS(
        recordingsDirectory: URL,
        modelsDirectory: URL,
        cachesDirectory: URL,
        temporaryDirectory: URL
    ) -> Self {
        Self(
            directoriesToRemove: [
                recordingsDirectory,
                modelsDirectory
            ],
            directoriesToEmpty: [
                cachesDirectory,
                temporaryDirectory
            ]
        )
    }

    public func performBestEffort(fileManager: FileManager = .default) {
        for directory in directoriesToRemove where fileManager.fileExists(atPath: directory.path) {
            try? fileManager.removeItem(at: directory)
        }

        for directory in directoriesToEmpty {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else {
                continue
            }

            for url in contents {
                try? fileManager.removeItem(at: url)
            }
        }
    }
}

public enum VoiceInkAppDataResetDiagnostics {
    public static func swiftDataResetFailedMessage(errorDescription: String) -> String {
        "Failed to reset SwiftData: \(errorDescription)"
    }
}

public protocol VoiceInkStoredAudioRecord: AnyObject {
    var audioFileURL: String? { get set }
    var storedAudioRecordingsDirectory: URL? { get }
}

public extension VoiceInkStoredAudioRecord {
    var storedAudioRecordingsDirectory: URL? {
        nil
    }

    func resolvedAudioFileURL(relativeTo recordingsDirectory: URL? = nil) -> URL? {
        VoiceInkStoredAudioFile.resolvedURL(
            for: audioFileURL,
            relativeTo: recordingsDirectory ?? storedAudioRecordingsDirectory
        )
    }

    func existingAudioFileURL(
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        VoiceInkStoredAudioFile.existingURL(
            for: audioFileURL,
            relativeTo: recordingsDirectory ?? storedAudioRecordingsDirectory,
            fileManager: fileManager
        )
    }

    func hasStoredAudioFile(
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        existingAudioFileURL(relativeTo: recordingsDirectory, fileManager: fileManager) != nil
    }

    func storedAudioAvailability(
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> VoiceInkStoredAudioAvailability {
        VoiceInkStoredAudioFile.availability(
            for: audioFileURL,
            relativeTo: recordingsDirectory ?? storedAudioRecordingsDirectory,
            fileManager: fileManager
        )
    }

    @discardableResult
    func deleteExistingAudioFile(
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL? {
        try VoiceInkStoredAudioFile.deleteExistingFile(
            for: audioFileURL,
            relativeTo: recordingsDirectory ?? storedAudioRecordingsDirectory,
            fileManager: fileManager
        )
    }

    @discardableResult
    func deleteExistingAudioFileReportingFailure(
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default,
        reportFailure: (String) -> Void
    ) -> URL? {
        VoiceInkStoredAudioFile.deleteExistingFileReportingFailure(
            for: audioFileURL,
            relativeTo: recordingsDirectory ?? storedAudioRecordingsDirectory,
            fileManager: fileManager,
            reportFailure: reportFailure
        )
    }

    @discardableResult
    func deleteExistingAudioFileAndClearReference(
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL? {
        guard let deletedURL = try deleteExistingAudioFile(
            relativeTo: recordingsDirectory,
            fileManager: fileManager
        ) else {
            return nil
        }

        audioFileURL = nil
        return deletedURL
    }
}
