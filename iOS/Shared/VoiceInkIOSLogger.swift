import OSLog
import VoiceInkCore

enum VoiceInkIOSLogger {
    static let app = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: VoiceInkIOSLogCategory.app)
    static let appGroup = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: VoiceInkIOSLogCategory.appGroup)
    static let audioPlayback = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: VoiceInkIOSLogCategory.audioPlayback)
    static let audioSession = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: VoiceInkIOSLogCategory.audioSession)
    static let keyboard = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: VoiceInkIOSLogCategory.keyboard)
    static let localWhisper = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: VoiceInkIOSLogCategory.localWhisper)
    static let localModelManagement = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: VoiceInkIOSLogCategory.localModelManagement)
    static let notes = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: VoiceInkIOSLogCategory.notes)
    static let recording = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: VoiceInkIOSLogCategory.recording)
    static let settings = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: VoiceInkIOSLogCategory.settings)
}
