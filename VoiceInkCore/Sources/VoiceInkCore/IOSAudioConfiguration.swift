public struct VoiceInkIOSAudioSessionRecordingConfiguration: Equatable, Sendable {
    public enum Category: String, Equatable, Sendable {
        case playAndRecord
    }

    public enum Mode: String, Equatable, Sendable {
        case spokenAudio
    }

    public enum Option: String, Equatable, Sendable {
        case defaultToSpeaker
        case allowBluetooth
        case allowBluetoothA2DP
        case mixWithOthers
    }

    public let category: Category
    public let mode: Mode
    public let options: [Option]

    public init(category: Category, mode: Mode, options: [Option]) {
        self.category = category
        self.mode = mode
        self.options = options
    }

    public static let voiceRecording = Self(
        category: .playAndRecord,
        mode: .spokenAudio,
        options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
    )
}

public struct VoiceInkIOSAudioPlaybackSessionConfiguration: Equatable, Sendable {
    public enum Category: String, Equatable, Sendable {
        case playback
    }

    public let category: Category

    public init(category: Category) {
        self.category = category
    }

    public static let notePlayback = Self(category: .playback)
}

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
