public enum VoiceInkTranscriptionModelProvider: String, CaseIterable, Sendable {
    case groq
    case openAI
    case assemblyAI
    case cartesia
    case deepgram
    case elevenLabs
    case mistral
    case gemini
    case soniox
    case speechmatics
    case xai
    case local

    public var providerKind: VoiceInkProviderKind? {
        switch self {
        case .groq:
            return .groq
        case .openAI:
            return .openAI
        case .assemblyAI:
            return .assemblyAI
        case .deepgram:
            return .deepgram
        case .elevenLabs:
            return .elevenLabs
        case .mistral:
            return .mistral
        case .gemini:
            return .gemini
        case .soniox:
            return .soniox
        case .speechmatics:
            return .speechmatics
        case .xai:
            return .xai
        case .local:
            return .localWhisper
        case .cartesia:
            return nil
        }
    }

    public var languageCodes: [String]? {
        switch self {
        case .assemblyAI:
            return ["en", "es", "de", "fr", "pt", "it"]
        case .cartesia:
            return [
                "af", "am", "ar", "as", "az", "ba", "be", "bg", "bn", "bo",
                "br", "bs", "ca", "cs", "cy", "da", "de", "el", "en", "es",
                "et", "eu", "fa", "fi", "fo", "fr", "gl", "gu", "ha", "haw",
                "he", "hi", "hr", "ht", "hu", "hy", "id", "is", "it", "ja",
                "jw", "ka", "kk", "km", "kn", "ko", "la", "lb", "ln", "lo",
                "lt", "lv", "mg", "mi", "mk", "ml", "mn", "mr", "ms", "mt",
                "my", "ne", "nl", "nn", "no", "oc", "pa", "pl", "ps", "pt",
                "ro", "ru", "sa", "sd", "si", "sk", "sl", "sn", "so", "sq",
                "sr", "su", "sv", "sw", "ta", "te", "tg", "th", "tk", "tl",
                "tr", "tt", "uk", "ur", "uz", "vi", "yi", "yo", "yue", "zh",
                "zu"
            ]
        case .xai:
            return [
                "ar", "cs", "da", "nl", "en", "fil", "fr", "de", "hi", "id",
                "it", "ja", "ko", "mk", "ms", "fa", "pl", "pt", "ro", "ru",
                "es", "sv", "th", "tr", "vi"
            ]
        case .elevenLabs:
            return [
                "af", "am", "ar", "as", "az", "be", "bg", "bn", "bs", "ca",
                "cs", "cy", "da", "de", "el", "en", "es", "et", "eu", "fa",
                "fi", "fil", "fr", "ga", "gl", "gu", "ha", "he", "hi", "hr",
                "hu", "hy", "id", "ig", "is", "it", "ja", "jw", "ka", "kk",
                "km", "kn", "ko", "ku", "ky", "lb", "ln", "lo", "lt", "lv",
                "mi", "mk", "ml", "mn", "mr", "ms", "mt", "my", "ne", "nl",
                "no", "or", "pa", "pl", "ps", "pt", "ro", "ru", "sd", "sk",
                "sl", "sn", "so", "sr", "sv", "sw", "ta", "tg", "te", "th",
                "tr", "uk", "ur", "uz", "vi", "wo", "xh", "yo", "yue", "zh",
                "zu"
            ]
        case .speechmatics:
            return [
                "ar", "ba", "eu", "be", "bn", "bg", "yue", "ca", "hr", "cs",
                "da", "nl", "en", "et", "fi", "fr", "gl", "de", "el", "he",
                "hi", "hu", "id", "it", "ja", "ko", "lv", "lt", "ms", "mt",
                "mr", "mn", "no", "fa", "pl", "pt", "ro", "ru", "sk", "sl",
                "es", "sw", "sv", "tl", "ta", "th", "tr", "uk", "ur", "vi",
                "cy", "zh"
            ]
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
        case .groq, .openAI, .gemini, .local:
            return nil
        }
    }

    public var includesAutoDetect: Bool {
        switch self {
        case .assemblyAI, .deepgram, .elevenLabs, .mistral, .soniox, .speechmatics, .xai:
            return true
        case .cartesia, .groq, .openAI, .gemini, .local:
            return false
        }
    }

    public var supportsRecordedFileTranscription: Bool {
        switch self {
        case .cartesia:
            return false
        case .assemblyAI, .deepgram, .elevenLabs, .mistral, .soniox, .speechmatics, .xai, .groq, .openAI, .gemini, .local:
            return true
        }
    }

    public var apiErrorDomain: String? {
        switch self {
        case .groq:
            return "GroqAPI"
        case .deepgram:
            return "DeepgramAPI"
        case .gemini:
            return "GeminiAPI"
        case .mistral:
            return "MistralAPI"
        case .elevenLabs:
            return "ElevenLabsAPI"
        case .soniox:
            return "SonioxAPI"
        case .speechmatics:
            return "SpeechmaticsAPI"
        case .assemblyAI:
            return "AssemblyAIAPI"
        case .xai:
            return "XAIAPI"
        case .openAI, .cartesia, .local:
            return nil
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

public struct VoiceInkNativeAppleTranscriptionModelSpec: Equatable, Sendable {
    public let name: String
    public let displayName: String
    public let description: String
    public let isMultilingual: Bool

    public var supportedLanguages: [String: String] {
        Self.supportedLanguages(isMultilingual: isMultilingual)
    }

    public init(
        name: String,
        displayName: String,
        description: String,
        isMultilingual: Bool
    ) {
        self.name = name
        self.displayName = displayName
        self.description = description
        self.isMultilingual = isMultilingual
    }

    public static func supportedLanguages(isMultilingual: Bool) -> [String: String] {
        isMultilingual ? VoiceInkLanguageCatalog.nativeApple : VoiceInkLanguageCatalog.englishOnly
    }
}

public struct VoiceInkFluidAudioTranscriptionModelSpec: Equatable, Sendable {
    public let name: String
    public let displayName: String
    public let description: String
    public let size: String
    public let speed: Double
    public let accuracy: Double
    public let ramUsage: Double
    public let isMultilingual: Bool
    public let supportsStreaming: Bool

    public var supportedLanguages: [String: String] {
        Self.supportedLanguages(isMultilingual: isMultilingual)
    }

    public init(
        name: String,
        displayName: String,
        description: String,
        size: String,
        speed: Double,
        accuracy: Double,
        ramUsage: Double,
        isMultilingual: Bool,
        supportsStreaming: Bool
    ) {
        self.name = name
        self.displayName = displayName
        self.description = description
        self.size = size
        self.speed = speed
        self.accuracy = accuracy
        self.ramUsage = ramUsage
        self.isMultilingual = isMultilingual
        self.supportsStreaming = supportsStreaming
    }

    public static func supportedLanguages(isMultilingual: Bool) -> [String: String] {
        VoiceInkLanguageCatalog.fluidAudioLanguages(isMultilingual: isMultilingual)
    }
}

public enum VoiceInkTranscriptionModelCatalog {
    public static let localBaseModel = "base"

    public static let nativeAppleModel = VoiceInkNativeAppleTranscriptionModelSpec(
        name: "apple-speech",
        displayName: "Apple Speech",
        description: "Uses the native Apple Speech framework for transcription. Requires macOS 26",
        isMultilingual: true
    )

    public static let fluidAudioModels = [
        VoiceInkFluidAudioTranscriptionModelSpec(
            name: "parakeet-tdt-0.6b-v2",
            displayName: "Parakeet V2",
            description: "NVIDIA's Parakeet V2 model optimized for lightning-fast English-only transcription",
            size: "474 MB",
            speed: 0.99,
            accuracy: 0.94,
            ramUsage: 0.8,
            isMultilingual: false,
            supportsStreaming: true
        ),
        VoiceInkFluidAudioTranscriptionModelSpec(
            name: "parakeet-tdt-0.6b-v3",
            displayName: "Parakeet V3",
            description: "Parakeet V3 with English and 25 European language support",
            size: "494 MB",
            speed: 0.99,
            accuracy: 0.94,
            ramUsage: 0.8,
            isMultilingual: true,
            supportsStreaming: true
        )
    ]

    public static func modelNames(for provider: VoiceInkTranscriptionModelProvider) -> [String] {
        switch provider {
        case .assemblyAI, .cartesia, .groq, .deepgram, .elevenLabs, .mistral, .gemini, .soniox, .speechmatics, .xai:
            return cloudModels(for: provider).map(\.name)
        case .openAI:
            return [
                "whisper-1",
                "gpt-4o-transcribe",
                "gpt-4o-mini-transcribe"
            ]
        case .local:
            return [localBaseModel]
        }
    }

    public static func cloudModels(for provider: VoiceInkTranscriptionModelProvider) -> [VoiceInkCloudTranscriptionModelSpec] {
        switch provider {
        case .assemblyAI:
            return [
                VoiceInkCloudTranscriptionModelSpec(
                    name: "universal-3-pro",
                    displayName: "Universal-3 Pro (AssemblyAI)",
                    description: "Highest-accuracy multilingual transcription with realtime support.",
                    speed: 0.94,
                    accuracy: 0.98,
                    isMultilingual: true,
                    supportsStreaming: true
                ),
                VoiceInkCloudTranscriptionModelSpec(
                    name: "universal-streaming",
                    displayName: "Universal-2 (AssemblyAI)",
                    description: "Balanced multilingual transcription with auto-detect.",
                    speed: 0.96,
                    accuracy: 0.92,
                    isMultilingual: true,
                    supportsStreaming: true
                )
            ]
        case .cartesia:
            return [
                VoiceInkCloudTranscriptionModelSpec(
                    name: "ink-whisper",
                    displayName: "Ink Whisper (Cartesia)",
                    description: "Cartesia's fastest streaming STT model — engineered for real-time voice agents with 90+ language support",
                    speed: 0.99,
                    accuracy: 0.94,
                    isMultilingual: true,
                    supportsStreaming: true
                )
            ]
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
        case .elevenLabs:
            return [
                VoiceInkCloudTranscriptionModelSpec(
                    name: "scribe_v1",
                    displayName: "Scribe v1 (ElevenLabs)",
                    description: "ElevenLabs' Scribe model for fast & accurate transcription",
                    speed: 0.7,
                    accuracy: 0.98,
                    isMultilingual: true
                ),
                VoiceInkCloudTranscriptionModelSpec(
                    name: "scribe_v2",
                    displayName: "Scribe V2 (ElevenLabs)",
                    description: "ElevenLabs' Scribe V2 model for the most accurate transcription",
                    speed: 0.99,
                    accuracy: 0.98,
                    isMultilingual: true,
                    supportsStreaming: true
                )
            ]
        case .xai:
            return [
                VoiceInkCloudTranscriptionModelSpec(
                    name: "grok-stt",
                    displayName: "Grok (xAI)",
                    description: "xAI's Grok speech-to-text with streaming and batch transcription",
                    speed: 0.99,
                    accuracy: 0.98,
                    isMultilingual: true,
                    supportsStreaming: true
                )
            ]
        case .speechmatics:
            return [
                VoiceInkCloudTranscriptionModelSpec(
                    name: "speechmatics-enhanced",
                    displayName: "Speechmatics",
                    description: "Speechmatics enhanced accuracy transcription with streaming and 50+ language support",
                    speed: 0.99,
                    accuracy: 0.98,
                    isMultilingual: true,
                    supportsStreaming: true
                )
            ]
        case .openAI, .local:
            return []
        }
    }
}
