import OSLog
import VoiceInkCore

enum VoiceInkIOSLogger {
    static let app = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "iOSApp")
    static let appGroup = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "iOSAppGroup")
    static let audioPlayback = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "iOSAudioPlayback")
    static let audioSession = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "iOSAudioSession")
    static let keyboard = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "iOSKeyboard")
    static let localWhisper = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "iOSLocalWhisper")
    static let localModelManagement = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "iOSLocalModelManagement")
    static let notes = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "iOSNotes")
    static let recording = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "iOSRecording")
    static let settings = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "iOSSettings")
}
