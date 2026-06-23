public struct VoiceInkIOSAudioRecorderConfiguration: Equatable, Sendable {
    public enum Format: String, Equatable, Sendable {
        case linearPCM
    }

    public enum Quality: String, Equatable, Sendable {
        case high
    }

    public let format: Format
    public let sampleRate: Double
    public let channelCount: Int
    public let bitDepth: Int
    public let isBigEndian: Bool
    public let isFloatingPoint: Bool
    public let quality: Quality
    public let isMeteringEnabled: Bool

    public init(
        format: Format,
        sampleRate: Double,
        channelCount: Int,
        bitDepth: Int,
        isBigEndian: Bool,
        isFloatingPoint: Bool,
        quality: Quality,
        isMeteringEnabled: Bool
    ) {
        self.format = format
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitDepth = bitDepth
        self.isBigEndian = isBigEndian
        self.isFloatingPoint = isFloatingPoint
        self.quality = quality
        self.isMeteringEnabled = isMeteringEnabled
    }

    public static let voiceRecording = Self(
        format: .linearPCM,
        sampleRate: VoiceInkPCM16Audio.mono16kSampleRate,
        channelCount: VoiceInkPCM16Audio.monoChannelCount,
        bitDepth: VoiceInkPCM16Audio.bitsPerSample,
        isBigEndian: VoiceInkPCM16Audio.isBigEndian,
        isFloatingPoint: VoiceInkPCM16Audio.isFloatingPoint,
        quality: .high,
        isMeteringEnabled: true
    )
}
