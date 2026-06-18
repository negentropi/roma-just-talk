import Foundation

public struct VoiceInkRecordingTranscriptionDraft: Equatable, Sendable {
    public let text: String
    public let duration: TimeInterval
    public let audioFileURL: String?
    public let transcriptionModelName: String?
    public let powerModeName: String?
    public let powerModeEmoji: String?
    public let transcriptionStatus: VoiceInkTranscriptionStatus

    public init(
        text: String,
        duration: TimeInterval,
        audioFileURL: String?,
        transcriptionModelName: String? = nil,
        powerModeName: String? = nil,
        powerModeEmoji: String? = nil,
        transcriptionStatus: VoiceInkTranscriptionStatus
    ) {
        self.text = text
        self.duration = duration
        self.audioFileURL = audioFileURL
        self.transcriptionModelName = transcriptionModelName
        self.powerModeName = powerModeName
        self.powerModeEmoji = powerModeEmoji
        self.transcriptionStatus = transcriptionStatus
    }

    public static func pending(
        duration: TimeInterval,
        audioFileURL: String?,
        transcriptionModelName: String? = nil,
        powerModeName: String? = nil,
        powerModeEmoji: String? = nil
    ) -> VoiceInkRecordingTranscriptionDraft {
        VoiceInkRecordingTranscriptionDraft(
            text: "",
            duration: duration,
            audioFileURL: audioFileURL,
            transcriptionModelName: transcriptionModelName,
            powerModeName: powerModeName,
            powerModeEmoji: powerModeEmoji,
            transcriptionStatus: .pending
        )
    }

    public static func canceled(
        duration: TimeInterval,
        audioFileURL: String?,
        transcriptionModelName: String? = nil,
        powerModeName: String? = nil,
        powerModeEmoji: String? = nil
    ) -> VoiceInkRecordingTranscriptionDraft {
        VoiceInkRecordingTranscriptionDraft(
            text: VoiceInkTranscriptPresentation.canceledTranscriptionText,
            duration: duration,
            audioFileURL: audioFileURL,
            transcriptionModelName: transcriptionModelName,
            powerModeName: powerModeName,
            powerModeEmoji: powerModeEmoji,
            transcriptionStatus: .canceled
        )
    }
}
