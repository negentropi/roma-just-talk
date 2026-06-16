import Foundation
import VoiceInkCore

// Enum to differentiate between model providers
enum ModelProvider: String, Codable, Hashable, CaseIterable {
    case whisper = "Whisper"
    case fluidAudio = "Parakeet"
    case groq = "Groq"
    case elevenLabs = "ElevenLabs"
    case deepgram = "Deepgram"
    case mistral = "Mistral"
    case gemini = "Gemini"
    case soniox = "Soniox"
    case speechmatics = "Speechmatics"
    case assemblyAI = "AssemblyAI"
    case xai = "xAI"
    case cartesia = "Cartesia"
    case custom = "Custom"
    case nativeApple = "Native Apple"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        // "Local" was the raw value before renaming to "Whisper"
        if raw == "Local" {
            self = .whisper
            return
        }
        guard let value = ModelProvider(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ModelProvider: \(raw)")
        }
        self = value
    }
}

extension ModelProvider {
    var coreProviderKind: VoiceInkProviderKind? {
        switch self {
        case .groq:
            return .groq
        case .deepgram:
            return .deepgram
        case .gemini:
            return .gemini
        default:
            return nil
        }
    }

    var coreTranscriptionModelProvider: VoiceInkTranscriptionModelProvider? {
        switch self {
        case .groq:
            return .groq
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
        case .cartesia:
            return .cartesia
        default:
            return nil
        }
    }

    var apiKeyProviderName: String {
        coreProviderKind?.displayName ?? rawValue
    }
}

// A unified protocol for any transcription model
protocol TranscriptionModel: Identifiable, Hashable {
    var id: UUID { get }
    var name: String { get }
    var displayName: String { get }
    var description: String { get }
    var provider: ModelProvider { get }
    
    // Language capabilities
    var isMultilingualModel: Bool { get }
    var supportedLanguages: [String: String] { get }

    var supportsStreaming: Bool { get }
}

extension TranscriptionModel {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var language: String {
        isMultilingualModel ? "Multilingual" : "English-only"
    }

    var supportsStreaming: Bool { false }

    var supportsRecordedFileTranscription: Bool {
        guard let cloudProvider = CloudProviderRegistry.provider(for: provider) else {
            return true
        }
        return !cloudProvider.isStreamingOnly
    }
}

// A new struct for Apple's native models
struct NativeAppleModel: TranscriptionModel {
    let id = UUID()
    let name: String
    let displayName: String
    let description: String
    let provider: ModelProvider = .nativeApple
    let isMultilingualModel: Bool
    let supportedLanguages: [String: String]
}

// A new struct for FluidAudio models
struct FluidAudioModel: TranscriptionModel {
    let id = UUID()
    let name: String
    let displayName: String
    let description: String
    let provider: ModelProvider = .fluidAudio
    let size: String
    let speed: Double
    let accuracy: Double
    let ramUsage: Double
    let supportsStreaming: Bool
    var isMultilingualModel: Bool {
        supportedLanguages.count > 1
    }
    let supportedLanguages: [String: String]

    init(name: String, displayName: String, description: String, size: String, speed: Double, accuracy: Double, ramUsage: Double, supportsStreaming: Bool = false, supportedLanguages: [String: String]) {
        self.name = name
        self.displayName = displayName
        self.description = description
        self.size = size
        self.speed = speed
        self.accuracy = accuracy
        self.ramUsage = ramUsage
        self.supportsStreaming = supportsStreaming
        self.supportedLanguages = supportedLanguages
    }
}

// A new struct for cloud models
struct CloudModel: TranscriptionModel {
    let id: UUID
    let name: String
    let displayName: String
    let description: String
    let provider: ModelProvider
    let speed: Double
    let accuracy: Double
    let isMultilingualModel: Bool
    let supportsStreaming: Bool
    let supportedLanguages: [String: String]

    init(id: UUID = UUID(), name: String, displayName: String, description: String, provider: ModelProvider, speed: Double, accuracy: Double, isMultilingual: Bool, supportsStreaming: Bool = false, supportedLanguages: [String: String]) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.description = description
        self.provider = provider
        self.speed = speed
        self.accuracy = accuracy
        self.isMultilingualModel = isMultilingual
        self.supportsStreaming = supportsStreaming
        self.supportedLanguages = supportedLanguages
    }
}

/// Custom cloud model with API key stored in Keychain.
struct CustomCloudModel: TranscriptionModel, Codable {
    let id: UUID
    let name: String
    let displayName: String
    let description: String
    let provider: ModelProvider = .custom
    let apiEndpoint: String
    let modelName: String
    let isMultilingualModel: Bool
    let supportedLanguages: [String: String]

    /// API key retrieved from Keychain by model ID.
    var apiKey: String {
        APIKeyManager.shared.getCustomModelAPIKey(forModelId: id) ?? ""
    }

    init(id: UUID = UUID(), name: String, displayName: String, description: String, apiEndpoint: String, modelName: String, isMultilingual: Bool = true, supportedLanguages: [String: String]? = nil) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.description = description
        self.apiEndpoint = apiEndpoint
        self.modelName = modelName
        self.isMultilingualModel = isMultilingual
        self.supportedLanguages = supportedLanguages ?? LanguageDictionary.forProvider(isMultilingual: isMultilingual)
    }

    /// Custom Codable to migrate legacy apiKey from JSON to Keychain.
    private enum CodingKeys: String, CodingKey {
        case id, name, displayName, description, apiEndpoint, modelName, isMultilingualModel, supportedLanguages
        case apiKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        displayName = try container.decode(String.self, forKey: .displayName)
        description = try container.decode(String.self, forKey: .description)
        apiEndpoint = try container.decode(String.self, forKey: .apiEndpoint)
        modelName = try container.decode(String.self, forKey: .modelName)
        isMultilingualModel = try container.decode(Bool.self, forKey: .isMultilingualModel)
        supportedLanguages = try container.decode([String: String].self, forKey: .supportedLanguages)

        if let legacyApiKey = try container.decodeIfPresent(String.self, forKey: .apiKey), !legacyApiKey.isEmpty {
            APIKeyManager.shared.saveCustomModelAPIKey(legacyApiKey, forModelId: id)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(description, forKey: .description)
        try container.encode(apiEndpoint, forKey: .apiEndpoint)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(isMultilingualModel, forKey: .isMultilingualModel)
        try container.encode(supportedLanguages, forKey: .supportedLanguages)
    }
} 

struct WhisperModel: TranscriptionModel {
    let id = UUID()
    let name: String
    let displayName: String
    let size: String
    let supportedLanguages: [String: String]
    let description: String
    let speed: Double
    let accuracy: Double
    let ramUsage: Double
    let provider: ModelProvider = .whisper

    var downloadURL: String {
        VoiceInkWhisperModelFiles.downloadURLString(forFilename: filename)
    }

    var filename: String {
        VoiceInkWhisperModelFiles.filename(forModelName: name)
    }

    var isMultilingualModel: Bool {
        supportedLanguages.count > 1
    }

    init(spec: VoiceInkWhisperModelFileSpec) {
        self.name = spec.modelName
        self.displayName = spec.displayName
        self.size = spec.size
        self.supportedLanguages = LanguageDictionary.forProvider(isMultilingual: spec.isMultilingual, provider: .whisper)
        self.description = spec.description
        self.speed = spec.speed
        self.accuracy = spec.accuracy
        self.ramUsage = spec.ramUsage
    }
} 

// User-imported local models 
struct ImportedWhisperModel: TranscriptionModel {
    let id = UUID()
    let name: String
    let displayName: String
    let description: String
    let provider: ModelProvider = .whisper
    let isMultilingualModel: Bool
    let supportedLanguages: [String: String]

    init(fileBaseName: String) {
        self.name = fileBaseName
        self.displayName = fileBaseName
        self.description = "Imported local model"
        self.isMultilingualModel = true
        self.supportedLanguages = LanguageDictionary.forProvider(isMultilingual: true, provider: .whisper)
    }
}
