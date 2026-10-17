import OSLog
import RomaCore

enum RomaIOSLogger {
    static let app = Logger(subsystem: RomaAppIdentity.loggingSubsystem, category: RomaIOSLogCategory.app)
    static let appGroup = Logger(subsystem: RomaAppIdentity.loggingSubsystem, category: RomaIOSLogCategory.appGroup)
    static let audioPlayback = Logger(subsystem: RomaAppIdentity.loggingSubsystem, category: RomaIOSLogCategory.audioPlayback)
    static let audioSession = Logger(subsystem: RomaAppIdentity.loggingSubsystem, category: RomaIOSLogCategory.audioSession)
    static let keyboard = Logger(subsystem: RomaAppIdentity.loggingSubsystem, category: RomaIOSLogCategory.keyboard)
    static let localWhisper = Logger(subsystem: RomaAppIdentity.loggingSubsystem, category: RomaIOSLogCategory.localWhisper)
    static let nativeAppleTranscription = Logger(subsystem: RomaAppIdentity.loggingSubsystem, category: RomaIOSLogCategory.nativeAppleTranscription)
    static let nativeAppleLanguageAssets = Logger(subsystem: RomaAppIdentity.loggingSubsystem, category: RomaIOSLogCategory.nativeAppleLanguageAssets)
    static let localModelManagement = Logger(subsystem: RomaAppIdentity.loggingSubsystem, category: RomaIOSLogCategory.localModelManagement)
    static let notes = Logger(subsystem: RomaAppIdentity.loggingSubsystem, category: RomaIOSLogCategory.notes)
    static let recording = Logger(subsystem: RomaAppIdentity.loggingSubsystem, category: RomaIOSLogCategory.recording)
    static let settings = Logger(subsystem: RomaAppIdentity.loggingSubsystem, category: RomaIOSLogCategory.settings)
}
