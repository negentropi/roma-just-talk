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

public struct VoiceInkTranscriptionRecordCancellationPlan: Equatable, Sendable {
    public let text: String
    public let enhancedText: String?
    public let status: VoiceInkTranscriptionStatus
    public let duration: TimeInterval?
    public let transcriptionModelName: String?
    public let aiEnhancementModelName: String?
    public let promptName: String?
    public let transcriptionDuration: TimeInterval?
    public let enhancementDuration: TimeInterval?
    public let aiRequestSystemMessage: String?
    public let aiRequestUserMessage: String?
    public let transcriptionError: String?

    public init(
        duration: TimeInterval? = nil,
        modelName: String? = nil
    ) {
        self.text = VoiceInkTranscriptPresentation.canceledTranscriptionText
        self.enhancedText = nil
        self.status = .canceled
        self.duration = duration
        self.transcriptionModelName = modelName
        self.aiEnhancementModelName = nil
        self.promptName = nil
        self.transcriptionDuration = nil
        self.enhancementDuration = nil
        self.aiRequestSystemMessage = nil
        self.aiRequestUserMessage = nil
        self.transcriptionError = nil
    }
}

public protocol VoiceInkMutableTranscriptionRecord: AnyObject {
    var text: String { get set }
    var enhancedText: String? { get set }
    var duration: TimeInterval { get set }
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

    func applyCancellationPlan(_ plan: VoiceInkTranscriptionRecordCancellationPlan) {
        text = plan.text
        enhancedText = plan.enhancedText
        if let duration = plan.duration {
            self.duration = duration
        }
        if let transcriptionModelName = plan.transcriptionModelName {
            self.transcriptionModelName = transcriptionModelName
        }
        aiEnhancementModelName = plan.aiEnhancementModelName
        transcriptionDuration = plan.transcriptionDuration
        enhancementDuration = plan.enhancementDuration
        transcriptionStatus = plan.status
        transcriptionError = plan.transcriptionError
    }

    func markTranscriptionCanceled(
        duration: TimeInterval? = nil,
        modelName: String? = nil
    ) {
        applyCancellationPlan(VoiceInkTranscriptionRecordCancellationPlan(
            duration: duration,
            modelName: modelName
        ))
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
