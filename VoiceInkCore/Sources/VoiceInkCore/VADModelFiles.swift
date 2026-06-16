import Foundation

public enum VoiceInkVADModelFiles {
    public static let sileroResourceName = "ggml-silero-v5.1.2"
    public static let sileroFileExtension = "bin"
    public static let sileroFilename = "\(sileroResourceName).\(sileroFileExtension)"

    public static func sileroURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: sileroResourceName, withExtension: sileroFileExtension)
    }

    public static func sileroPath(in bundle: Bundle = .main) -> String? {
        sileroURL(in: bundle)?.path
    }
}
