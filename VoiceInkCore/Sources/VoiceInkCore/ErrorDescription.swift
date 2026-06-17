import Foundation

public enum VoiceInkErrorDescription {
    public static func text(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
