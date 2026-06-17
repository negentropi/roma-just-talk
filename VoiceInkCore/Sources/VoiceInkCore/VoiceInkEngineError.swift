import Foundation

public enum VoiceInkEngineError: Error, Identifiable, Sendable {
    case modelLoadFailed
    case transcriptionFailed
    case whisperCoreFailed
    case unzipFailed
    case unknownError
    case localModelUnavailable
    case localModelLoadFailed
    case audioProcessingFailed
    case whisperTranscriptionFailed

    public var id: String { UUID().uuidString }
}

extension VoiceInkEngineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .modelLoadFailed:
            return "Failed to load the transcription model."
        case .transcriptionFailed:
            return "Failed to transcribe the audio."
        case .whisperCoreFailed:
            return "The core transcription engine failed."
        case .unzipFailed:
            return "Failed to unzip the downloaded Core ML model."
        case .unknownError:
            return "An unknown error occurred."
        case .localModelUnavailable:
            return "No local Whisper model is available. Please download a model first."
        case .localModelLoadFailed:
            return "Failed to load the Whisper model."
        case .audioProcessingFailed:
            return "Failed to process audio file for transcription."
        case .whisperTranscriptionFailed:
            return "Whisper transcription failed."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .modelLoadFailed:
            return "Try selecting a different model or redownloading the current model."
        case .transcriptionFailed:
            return "Check the default model try again. If the problem persists, try a different model."
        case .whisperCoreFailed:
            return "This can happen due to an issue with the audio recording or insufficient system resources. Please try again, or restart the app."
        case .unzipFailed:
            return "The downloaded Core ML model archive might be corrupted. Try deleting the model and downloading it again. Check available disk space."
        case .unknownError:
            return "Please restart the application. If the problem persists, contact support."
        case .localModelUnavailable:
            return "Download a local Whisper model before recording or retrying."
        case .localModelLoadFailed:
            return "Try redownloading the selected Whisper model."
        case .audioProcessingFailed:
            return "Check that the recording file exists and is a valid WAV recording."
        case .whisperTranscriptionFailed:
            return "Try recording again or switch to a different local model."
        }
    }
}
