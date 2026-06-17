public protocol VoiceInkMutableTranscriptionRecord: AnyObject {
    var text: String { get set }
    var enhancedText: String? { get set }
    var transcriptionModelName: String? { get set }
    var aiEnhancementModelName: String? { get set }
    var transcriptionStatus: VoiceInkTranscriptionStatus { get set }
    var transcriptionError: String? { get set }
}

public extension VoiceInkMutableTranscriptionRecord {
    func applyCompletedRunResult(_ result: VoiceInkTranscriptionRunResult) {
        text = result.cleanedText
        enhancedText = result.enhancedText
        transcriptionModelName = result.transcriptionModelName
        aiEnhancementModelName = result.aiEnhancementModelName
        transcriptionStatus = .completed
        transcriptionError = result.postProcessingError
    }

    func markTranscriptionFailed(_ errorDescription: String) {
        transcriptionStatus = .failed
        transcriptionError = errorDescription
    }
}
