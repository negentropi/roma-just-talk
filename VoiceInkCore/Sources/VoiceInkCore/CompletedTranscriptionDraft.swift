import Foundation

public enum VoiceInkEnhancementFailureDraftPolicy: Equatable, Sendable {
    case omitEnhancedText
    case storeFailureText
}

public struct VoiceInkAudioFileTranscriptionDraftContext: Equatable, Sendable {
    public let cleanedText: String
    public let duration: TimeInterval
    public let audioFileURL: String?
    public let transcriptionModelName: String?
    public let transcriptionDuration: TimeInterval?
    public let powerModeName: String?
    public let powerModeEmoji: String?

    public init(
        cleanedText: String,
        duration: TimeInterval,
        audioFileURL: String?,
        transcriptionModelName: String?,
        transcriptionDuration: TimeInterval?,
        powerModeName: String? = nil,
        powerModeEmoji: String? = nil
    ) {
        self.cleanedText = cleanedText
        self.duration = duration
        self.audioFileURL = audioFileURL
        self.transcriptionModelName = transcriptionModelName
        self.transcriptionDuration = transcriptionDuration
        self.powerModeName = powerModeName
        self.powerModeEmoji = powerModeEmoji
    }
}

public enum VoiceInkAudioFileTranscriptionEnhancementOutcome: Equatable, Sendable {
    case notAttempted
    case succeeded(VoiceInkAIEnhancementResult)
    case failed(reason: String, policy: VoiceInkEnhancementFailureDraftPolicy)
}

public struct VoiceInkAudioFileTranscriptionCompletionResult: Equatable, Sendable {
    public let draft: VoiceInkCompletedTranscriptionDraft
    public let enhancementFailureReason: String?

    public init(
        draft: VoiceInkCompletedTranscriptionDraft,
        enhancementFailureReason: String? = nil
    ) {
        self.draft = draft
        self.enhancementFailureReason = enhancementFailureReason
    }
}

public enum VoiceInkAudioFileTranscriptionDraft {
    public static func completed(
        context: VoiceInkAudioFileTranscriptionDraftContext,
        enhancementOutcome: VoiceInkAudioFileTranscriptionEnhancementOutcome = .notAttempted
    ) -> VoiceInkCompletedTranscriptionDraft {
        switch enhancementOutcome {
        case .notAttempted:
            return VoiceInkCompletedTranscriptionDraft(
                cleanedText: context.cleanedText,
                duration: context.duration,
                audioFileURL: context.audioFileURL,
                transcriptionModelName: context.transcriptionModelName,
                transcriptionDuration: context.transcriptionDuration,
                powerModeName: context.powerModeName,
                powerModeEmoji: context.powerModeEmoji
            )
        case .succeeded(let enhancementResult):
            return VoiceInkCompletedTranscriptionDraft(
                cleanedText: context.cleanedText,
                duration: context.duration,
                audioFileURL: context.audioFileURL,
                transcriptionModelName: context.transcriptionModelName,
                transcriptionDuration: context.transcriptionDuration,
                powerModeName: context.powerModeName,
                powerModeEmoji: context.powerModeEmoji,
                enhancementResult: enhancementResult
            )
        case .failed(let reason, let policy):
            return VoiceInkCompletedTranscriptionDraft(
                cleanedText: context.cleanedText,
                duration: context.duration,
                audioFileURL: context.audioFileURL,
                transcriptionModelName: context.transcriptionModelName,
                transcriptionDuration: context.transcriptionDuration,
                powerModeName: context.powerModeName,
                powerModeEmoji: context.powerModeEmoji,
                enhancementFailureReason: reason,
                enhancementFailurePolicy: policy
            )
        }
    }

    public static func completionResult(
        context: VoiceInkAudioFileTranscriptionDraftContext,
        enhancementRequest: VoiceInkTranscriptionEnhancementRequest?,
        enhancementFailurePolicy: VoiceInkEnhancementFailureDraftPolicy,
        enhance: (VoiceInkTranscriptionEnhancementRequest) async throws -> VoiceInkAIEnhancementResult
    ) async -> VoiceInkAudioFileTranscriptionCompletionResult {
        guard let enhancementRequest else {
            return VoiceInkAudioFileTranscriptionCompletionResult(
                draft: completed(context: context)
            )
        }

        do {
            let enhancement = try await enhance(enhancementRequest)
            return VoiceInkAudioFileTranscriptionCompletionResult(
                draft: completed(
                    context: context,
                    enhancementOutcome: .succeeded(enhancement)
                )
            )
        } catch {
            let reason = VoiceInkErrorDescription.text(for: error)
            return VoiceInkAudioFileTranscriptionCompletionResult(
                draft: completed(
                    context: context,
                    enhancementOutcome: .failed(
                        reason: reason,
                        policy: enhancementFailurePolicy
                    )
                ),
                enhancementFailureReason: reason
            )
        }
    }
}

public struct VoiceInkCompletedTranscriptionDraft: Equatable, Sendable {
    public let text: String
    public let duration: TimeInterval
    public let enhancedText: String?
    public let audioFileURL: String?
    public let transcriptionModelName: String?
    public let aiEnhancementModelName: String?
    public let promptName: String?
    public let transcriptionDuration: TimeInterval?
    public let enhancementDuration: TimeInterval?
    public let aiRequestSystemMessage: String?
    public let aiRequestUserMessage: String?
    public let powerModeName: String?
    public let powerModeEmoji: String?
    public let transcriptionStatus: VoiceInkTranscriptionStatus

    public init(
        cleanedText: String,
        duration: TimeInterval,
        audioFileURL: String?,
        transcriptionModelName: String?,
        transcriptionDuration: TimeInterval?,
        powerModeName: String? = nil,
        powerModeEmoji: String? = nil,
        enhancementResult: VoiceInkAIEnhancementResult? = nil,
        enhancementFailureReason: String? = nil,
        enhancementFailurePolicy: VoiceInkEnhancementFailureDraftPolicy = .omitEnhancedText
    ) {
        self.text = cleanedText
        self.duration = duration
        self.audioFileURL = audioFileURL
        self.transcriptionModelName = transcriptionModelName
        self.transcriptionDuration = transcriptionDuration
        self.powerModeName = powerModeName
        self.powerModeEmoji = powerModeEmoji
        self.transcriptionStatus = .completed

        if let enhancementResult {
            self.enhancedText = enhancementResult.text
            self.aiEnhancementModelName = enhancementResult.modelName
            self.promptName = enhancementResult.promptName
            self.enhancementDuration = enhancementResult.duration
            self.aiRequestSystemMessage = enhancementResult.requestSystemMessage
            self.aiRequestUserMessage = enhancementResult.requestUserMessage
        } else {
            switch enhancementFailurePolicy {
            case .omitEnhancedText:
                self.enhancedText = nil
            case .storeFailureText:
                self.enhancedText = enhancementFailureReason.map {
                    VoiceInkPostProcessingFailurePresentation.enhancementFailureText(reason: $0)
                }
            }
            self.aiEnhancementModelName = nil
            self.promptName = nil
            self.enhancementDuration = nil
            self.aiRequestSystemMessage = nil
            self.aiRequestUserMessage = nil
        }
    }
}
