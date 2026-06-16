public enum VoiceInkTranscriptionModelProvider: String, CaseIterable, Sendable {
    case groq
    case openAI
    case deepgram
    case mistral
    case gemini
    case soniox
    case local
    case voiceInk

    public var languageCodes: [String]? {
        switch self {
        case .soniox:
            return [
                "af", "sq", "ar", "az", "eu", "be", "bn", "bs", "bg", "ca",
                "zh", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "gl",
                "de", "el", "gu", "he", "hi", "hu", "id", "it", "ja", "kn",
                "kk", "ko", "lv", "lt", "mk", "ms", "ml", "mr", "no", "fa",
                "pl", "pt", "pa", "ro", "ru", "sr", "sk", "sl", "es", "sw",
                "sv", "tl", "ta", "te", "th", "tr", "uk", "ur", "vi", "cy"
            ]
        case .mistral:
            return ["ar", "de", "en", "es", "fr", "hi", "it", "ja", "ko", "nl", "pt", "ru", "zh"]
        case .deepgram:
            return [
                "ar", "be", "bg", "bn", "bs", "ca", "cs", "da", "de", "el",
                "en", "es", "et", "fa", "fi", "fr", "he", "hi", "hr", "hu",
                "id", "it", "ja", "kn", "ko", "lt", "lv", "mk", "mr", "ms",
                "nl", "no", "pl", "pt", "ro", "ru", "sk", "sl", "sr", "sv",
                "ta", "te", "th", "tl", "tr", "uk", "ur", "vi", "zh"
            ]
        case .groq, .openAI, .gemini, .local, .voiceInk:
            return nil
        }
    }

    public var includesAutoDetect: Bool {
        switch self {
        case .deepgram, .mistral, .soniox:
            return true
        case .groq, .openAI, .gemini, .local, .voiceInk:
            return false
        }
    }
}

public struct VoiceInkCloudTranscriptionModelSpec: Equatable, Sendable {
    public let name: String
    public let displayName: String
    public let description: String
    public let speed: Double
    public let accuracy: Double
    public let isMultilingual: Bool
    public let supportsStreaming: Bool

    public init(
        name: String,
        displayName: String,
        description: String,
        speed: Double,
        accuracy: Double,
        isMultilingual: Bool,
        supportsStreaming: Bool = false
    ) {
        self.name = name
        self.displayName = displayName
        self.description = description
        self.speed = speed
        self.accuracy = accuracy
        self.isMultilingual = isMultilingual
        self.supportsStreaming = supportsStreaming
    }
}

public enum VoiceInkTranscriptionModelCatalog {
    public static let voiceInkTranscriptionModel = "whisper-large-v3"
    public static let localBaseModel = "base"

    public static func modelNames(for provider: VoiceInkTranscriptionModelProvider) -> [String] {
        switch provider {
        case .groq, .deepgram, .mistral, .gemini, .soniox:
            return cloudModels(for: provider).map(\.name)
        case .openAI:
            return [
                "whisper-1",
                "gpt-4o-transcribe",
                "gpt-4o-mini-transcribe"
            ]
        case .local:
            return [localBaseModel]
        case .voiceInk:
            return []
        }
    }

    public static func cloudModels(for provider: VoiceInkTranscriptionModelProvider) -> [VoiceInkCloudTranscriptionModelSpec] {
        switch provider {
        case .groq:
            return [
                VoiceInkCloudTranscriptionModelSpec(
                    name: "whisper-large-v3-turbo",
                    displayName: "Whisper Large v3 Turbo (Groq)",
                    description: "Whisper Large v3 Turbo model with Groq's lightning-speed inference",
                    speed: 0.65,
                    accuracy: 0.95,
                    isMultilingual: true
                )
            ]
        case .deepgram:
            return [
                VoiceInkCloudTranscriptionModelSpec(
                    name: "nova-3",
                    displayName: "Nova 3 (Deepgram)",
                    description: "Deepgram's latest Nova 3 model for fast, accurate transcription",
                    speed: 0.99,
                    accuracy: 0.96,
                    isMultilingual: true,
                    supportsStreaming: true
                ),
                VoiceInkCloudTranscriptionModelSpec(
                    name: "nova-3-medical",
                    displayName: "Nova 3 Medical (Deepgram)",
                    description: "Specialized medical transcription model optimized for clinical environments",
                    speed: 0.99,
                    accuracy: 0.96,
                    isMultilingual: false,
                    supportsStreaming: true
                )
            ]
        case .mistral:
            return [
                VoiceInkCloudTranscriptionModelSpec(
                    name: "voxtral-mini-latest",
                    displayName: "Voxtral (Mistral)",
                    description: "Mistral's Voxtral model for fast and accurate transcription",
                    speed: 0.99,
                    accuracy: 0.98,
                    isMultilingual: true,
                    supportsStreaming: true
                )
            ]
        case .gemini:
            return [
                VoiceInkCloudTranscriptionModelSpec(
                    name: "gemini-2.5-pro",
                    displayName: "Gemini 2.5 Pro",
                    description: "Google's advanced model with high-quality transcription capabilities",
                    speed: 0.7,
                    accuracy: 0.97,
                    isMultilingual: true
                ),
                VoiceInkCloudTranscriptionModelSpec(
                    name: "gemini-2.5-flash",
                    displayName: "Gemini 2.5 Flash",
                    description: "Google's optimized model for low-latency transcription",
                    speed: 0.9,
                    accuracy: 0.95,
                    isMultilingual: true
                ),
                VoiceInkCloudTranscriptionModelSpec(
                    name: "gemini-3.1-pro-preview",
                    displayName: "Gemini 3.1 Pro",
                    description: "Google's latest model with enhanced transcription capabilities",
                    speed: 0.75,
                    accuracy: 0.97,
                    isMultilingual: true
                ),
                VoiceInkCloudTranscriptionModelSpec(
                    name: "gemini-3-flash-preview",
                    displayName: "Gemini 3 Flash",
                    description: "Google's newest fast model combining intelligence with superior speed",
                    speed: 0.92,
                    accuracy: 0.95,
                    isMultilingual: true
                )
            ]
        case .soniox:
            return [
                VoiceInkCloudTranscriptionModelSpec(
                    name: "stt-async-v4",
                    displayName: "Soniox V4",
                    description: "Soniox transcription model v4 with human-parity accuracy",
                    speed: 0.99,
                    accuracy: 0.98,
                    isMultilingual: true,
                    supportsStreaming: true
                )
            ]
        case .openAI, .local, .voiceInk:
            return []
        }
    }
}
