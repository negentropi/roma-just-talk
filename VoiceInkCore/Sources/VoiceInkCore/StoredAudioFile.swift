import Foundation

public enum VoiceInkStoredAudioFile {
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
        return recordingsDirectory.appendingPathComponent(storedValue)
    }

    public static func resolvedPath(
        for storedValue: String?,
        relativeTo recordingsDirectory: URL? = nil
    ) -> String? {
        resolvedURL(for: storedValue, relativeTo: recordingsDirectory)?.path
    }

    public static func fileExists(
        for storedValue: String?,
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let url = resolvedURL(for: storedValue, relativeTo: recordingsDirectory) else {
            return false
        }
        return fileManager.fileExists(atPath: url.path)
    }

    private static func cleanedStoredValue(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
