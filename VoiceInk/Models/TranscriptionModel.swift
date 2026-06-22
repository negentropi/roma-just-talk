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
        case .assemblyAI:
            return .assemblyAI
        case .xai:
            return .xai
        case .cartesia:
            return .cartesia
        default:
            return nil
        }
    }

    var apiKeyProviderName: String {
        coreTranscriptionModelProvider?.providerKind?.displayName ?? rawValue
    }

    fileprivate var transcriptionLanguageSource: VoiceInkTranscriptionLanguageSource {
        switch self {
        case .whisper:
            return .whisper
        case .nativeApple:
            return .nativeApple
        case .fluidAudio:
            return .fluidAudio
        default:
            guard let coreProvider = coreTranscriptionModelProvider else {
                return .all
            }
            return .provider(coreProvider)
        }
    }

    func supportedLanguages(isMultilingual: Bool) -> [String: String] {
        VoiceInkTranscriptionLanguageSupport.languages(
            for: transcriptionLanguageSource,
            isMultilingual: isMultilingual
        )
    }

    var modelManagementCategory: VoiceInkModelManagementModelCategory {
        switch self {
        case .whisper, .nativeApple, .fluidAudio:
            return .local
        case .custom:
            return .custom
        default:
            return .cloud
        }
    }

    var transcriptionServiceRoute: VoiceInkTranscriptionServiceRoute {
        switch self {
        case .whisper:
            return .localWhisper
        case .fluidAudio:
            return .localFluidAudio
        case .nativeApple:
            return .nativeApple
        default:
            return .cloud
        }
    }

    var transcriptionModelAvailabilityRequirement: VoiceInkTranscriptionModelAvailabilityRequirement {
        switch self {
        case .whisper:
            return .downloadedLocalWhisperModel
        case .fluidAudio:
            return .downloadedLocalFluidAudioModel
        case .nativeApple:
            return .currentOSSupport
        case .custom:
            return .alwaysAvailable
        default:
            return coreTranscriptionModelProvider == nil ? .unavailable : .configuredAPIKey
        }
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
        VoiceInkModelManagementPresentation.languageLabel(isMultilingual: isMultilingualModel)
    }

    var supportsStreaming: Bool { false }

    var supportsRecordedFileTranscription: Bool {
        provider.coreTranscriptionModelProvider?.supportsRecordedFileTranscription ?? true
    }

    var streamingPreferenceSnapshot: VoiceInkTranscriptionStreamingModelSnapshot {
        VoiceInkTranscriptionStreamingModelSnapshot(
            name: name,
            supportsStreaming: supportsStreaming,
            isStreamingOnly: CloudProviderRegistry.provider(for: provider)?.isStreamingOnly ?? false
        )
    }

    var transcriptionSessionRouteFacts: VoiceInkTranscriptionSessionRouteFacts {
        VoiceInkTranscriptionSessionRouteFacts(
            serviceRoute: provider.transcriptionServiceRoute,
            streamingSnapshot: streamingPreferenceSnapshot
        )
    }

    var streamingConnectionModelName: String {
        provider.coreTranscriptionModelProvider?.streamingConnectionModelName(for: name) ?? name
    }

    var mapsStreamingTransportTimeoutToFinalTimeout: Bool {
        provider.coreTranscriptionModelProvider?.mapsStreamingTransportTimeoutToFinalTimeout ?? false
    }

    var transcriptionRuntimeResourcePlan: VoiceInkTranscriptionRuntimeResourcePlan {
        VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: provider.transcriptionServiceRoute)
    }

    func transcriptionModelAvailabilityFacts(
        hasConfiguredAPIKey: Bool = false,
        isAvailableOnCurrentOS: Bool = true,
        isLocalFluidAudioModelDownloaded: Bool = false,
        isLocalWhisperModelDownloaded: Bool = false
    ) -> VoiceInkTranscriptionModelAvailabilityFacts {
        VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: provider.transcriptionModelAvailabilityRequirement,
            hasConfiguredAPIKey: hasConfiguredAPIKey,
            isAvailableOnCurrentOS: isAvailableOnCurrentOS,
            isLocalFluidAudioModelDownloaded: isLocalFluidAudioModelDownloaded,
            isLocalWhisperModelDownloaded: isLocalWhisperModelDownloaded
        )
    }

    var transcriptionLanguageOptions: [String: String] {
        if provider == .assemblyAI {
            return VoiceInkTranscriptionLanguageSupport.languages(
                for: provider.transcriptionLanguageSource,
                assemblyAIUsesRealtime: VoiceInkTranscriptionStreamingPreference.shouldUseStreaming(
                    for: streamingPreferenceSnapshot
                )
            )
        }

        return supportedLanguages
    }

    var transcriptionLanguageSelectionFacts: VoiceInkTranscriptionLanguageSelectionFacts {
        VoiceInkTranscriptionLanguageSelectionFacts(
            source: provider.transcriptionLanguageSource,
            isMultilingual: isMultilingualModel,
            languageOptions: transcriptionLanguageOptions
        )
    }

    func validTranscriptionLanguageOrFallback(_ language: String?) -> String {
        transcriptionLanguageSelectionFacts.compatibleLanguage(language)
    }

    var powerModeTranscriptionModelFacts: VoiceInkPowerModeTranscriptionModelFacts {
        VoiceInkPowerModeTranscriptionModelFacts(
            name: name,
            languageSource: provider.transcriptionLanguageSource,
            isMultilingual: isMultilingualModel,
            languageOptions: transcriptionLanguageOptions
        )
    }

    var powerModeTranscriptionModelResourceFacts: VoiceInkPowerModeTranscriptionModelResourceFacts {
        VoiceInkPowerModeTranscriptionModelResourceFacts(
            name: name,
            languageSource: provider.transcriptionLanguageSource
        )
    }

    func modelManagementFacts(isAvailableOnCurrentOS: Bool) -> VoiceInkModelManagementModelFacts {
        VoiceInkModelManagementModelFacts(
            name: name,
            category: provider.modelManagementCategory,
            isAvailableOnCurrentOS: isAvailableOnCurrentOS
        )
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

    init(spec: VoiceInkNativeAppleTranscriptionModelSpec) {
        self.name = spec.name
        self.displayName = spec.displayName
        self.description = spec.description
        self.isMultilingualModel = spec.isMultilingual
        self.supportedLanguages = spec.supportedLanguages
    }
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

    init(spec: VoiceInkFluidAudioTranscriptionModelSpec) {
        self.init(
            name: spec.name,
            displayName: spec.displayName,
            description: spec.description,
            size: spec.size,
            speed: spec.speed,
            accuracy: spec.accuracy,
            ramUsage: spec.ramUsage,
            supportsStreaming: spec.supportsStreaming,
            supportedLanguages: spec.supportedLanguages
        )
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
        self.supportedLanguages = supportedLanguages ?? ModelProvider.whisper.supportedLanguages(isMultilingual: isMultilingual)
    }

    init(from decoder: Decoder) throws {
        let record = try VoiceInkCustomCloudModelStoredRecord(from: decoder)
        id = record.id
        name = record.name
        displayName = record.displayName
        description = record.description
        apiEndpoint = record.apiEndpoint
        modelName = record.modelName
        isMultilingualModel = record.isMultilingualModel
        supportedLanguages = record.supportedLanguages

        if let legacyApiKey = record.legacyAPIKeyForKeychainMigration {
            APIKeyManager.shared.saveCustomModelAPIKey(legacyApiKey, forModelId: record.id)
        }
    }

    func encode(to encoder: Encoder) throws {
        try VoiceInkCustomCloudModelStoredRecord(
            id: id,
            name: name,
            displayName: displayName,
            description: description,
            apiEndpoint: apiEndpoint,
            modelName: modelName,
            isMultilingualModel: isMultilingualModel,
            supportedLanguages: supportedLanguages
        ).encode(to: encoder)
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

    var isMultilingualModel: Bool {
        supportedLanguages.count > 1
    }

    init(spec: VoiceInkWhisperModelFileSpec) {
        self.name = spec.modelName
        self.displayName = spec.displayName
        self.size = spec.size
        self.supportedLanguages = ModelProvider.whisper.supportedLanguages(isMultilingual: spec.isMultilingual)
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
        self.description = VoiceInkModelManagementPresentation.importedLocalModelDescription
        self.isMultilingualModel = true
        self.supportedLanguages = ModelProvider.whisper.supportedLanguages(isMultilingual: true)
    }
}
