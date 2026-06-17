import Foundation

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

    public static func fileExists(
        for storedValue: String?,
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        existingURL(for: storedValue, relativeTo: recordingsDirectory, fileManager: fileManager) != nil
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

    private static func cleanedStoredValue(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
}
