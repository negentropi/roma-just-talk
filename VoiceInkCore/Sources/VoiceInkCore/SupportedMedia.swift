import Foundation
import UniformTypeIdentifiers

public enum VoiceInkSupportedMedia {
    public static let fileExtensions: Set<String> = [
        "wav", "mp3", "m4a", "aiff", "mp4", "mov", "aac", "flac", "caf",
        "amr", "ogg", "oga", "opus", "3gp"
    ]

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
