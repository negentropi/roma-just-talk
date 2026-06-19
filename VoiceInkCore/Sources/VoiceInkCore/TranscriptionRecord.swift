import Foundation

public struct VoiceInkTranscriptionRecordFailurePlan: Equatable, Sendable {
    public let errorDescription: String
    public let status: VoiceInkTranscriptionStatus
    public let failedTranscriptText: String

    public init(errorDescription: String) {
        self.errorDescription = errorDescription
        self.status = .failed
        self.failedTranscriptText = VoiceInkTranscriptPresentation.failedTranscriptText(reason: errorDescription)
    }
}

public protocol VoiceInkMutableTranscriptionRecord: AnyObject {
    var text: String { get set }
    var enhancedText: String? { get set }
    var transcriptionModelName: String? { get set }
    var aiEnhancementModelName: String? { get set }
    var transcriptionDuration: TimeInterval? { get set }
    var enhancementDuration: TimeInterval? { get set }
    var transcriptionStatus: VoiceInkTranscriptionStatus { get set }
    var transcriptionError: String? { get set }
}

public extension VoiceInkMutableTranscriptionRecord {
    func applyCompletedRunResult(_ result: VoiceInkTranscriptionRunResult) {
        text = result.cleanedText
        enhancedText = result.enhancedText
        transcriptionModelName = result.transcriptionModelName
        aiEnhancementModelName = result.aiEnhancementModelName
        transcriptionDuration = result.transcriptionDuration
        enhancementDuration = result.enhancementDuration
        transcriptionStatus = .completed
        transcriptionError = result.postProcessingError
    }

    func markTranscriptionFailed(_ errorDescription: String) {
        let plan = VoiceInkTranscriptionRecordFailurePlan(errorDescription: errorDescription)
        transcriptionStatus = plan.status
        transcriptionError = plan.errorDescription
    }
}

public extension VoiceInkMutableTranscriptionRecord where Self: VoiceInkStoredAudioRecord {
    @discardableResult
    func retranscribeStoredAudio(
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default,
        transcribe: (URL) async throws -> VoiceInkTranscriptionRunResult
    ) async throws -> String {
        guard let fileURL = existingAudioFileURL(relativeTo: recordingsDirectory, fileManager: fileManager) else {
            let error = VoiceInkEngineError.audioFileNotFound
            markTranscriptionFailed(VoiceInkErrorDescription.text(for: error))
            throw error
        }

        do {
            let result = try await transcribe(fileURL)
            applyCompletedRunResult(result)
            return result.finalText
        } catch {
            markTranscriptionFailed(VoiceInkErrorDescription.text(for: error))
            throw error
        }
    }
}
