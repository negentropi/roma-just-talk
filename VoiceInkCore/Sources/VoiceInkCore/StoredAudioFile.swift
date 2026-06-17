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

    private static func cleanedStoredValue(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
