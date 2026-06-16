public enum VoiceInkTranscriptionStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case completed
    case failed
    case canceled
}
