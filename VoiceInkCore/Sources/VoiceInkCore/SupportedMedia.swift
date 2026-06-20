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
