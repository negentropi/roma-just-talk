import Foundation
import RomaCore

// A unified protocol for any transcription model
protocol TranscriptionModel: Identifiable, Hashable {
    var id: UUID { get }
    var name: String { get }
    var displayName: String { get }
    var description: String { get }
    var provider: RomaMacOSTranscriptionModelProvider { get }
    
    // Language capabilities
    var isMultilingualModel: Bool { get }
    var supportedLanguages: [String: String] { get }

    var supportsStreaming: Bool { get }
}

extension TranscriptionModel {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    private var coreFacts: RomaMacOSTranscriptionModelFacts {
        RomaMacOSTranscriptionModelFacts(
            name: name,
            provider: provider,
            isMultilingual: isMultilingualModel,
            supportedLanguages: supportedLanguages,
            supportsStreaming: supportsStreaming
        )
    }

    var language: String {
        RomaModelManagementPresentation.languageLabel(isMultilingual: isMultilingualModel)
    }

    var supportsStreaming: Bool { false }

    var supportsRecordedFileTranscription: Bool {
        coreFacts.supportsRecordedFileTranscription
    }

    var streamingPreferenceSnapshot: RomaTranscriptionStreamingModelSnapshot {
        coreFacts.streamingPreferenceSnapshot
    }

    var transcriptionSessionRouteFacts: RomaTranscriptionSessionRouteFacts {
        coreFacts.transcriptionSessionRouteFacts
    }

    var streamingConnectionModelName: String {
        coreFacts.streamingConnectionModelName
    }

    var mapsStreamingTransportTimeoutToFinalTimeout: Bool {
        coreFacts.mapsStreamingTransportTimeoutToFinalTimeout
    }

    var transcriptionRuntimeResourcePlan: RomaTranscriptionRuntimeResourcePlan {
        coreFacts.transcriptionRuntimeResourcePlan
    }

    func transcriptionModelAvailabilityFacts(
        hasConfiguredAPIKey: Bool = false,
        isAvailableOnCurrentOS: Bool = true,
        isLocalFluidAudioModelDownloaded: Bool = false,
        isLocalWhisperModelDownloaded: Bool = false,
        isLocalQwenModelDownloaded: Bool = false
    ) -> RomaTranscriptionModelAvailabilityFacts {
        coreFacts.transcriptionModelAvailabilityFacts(
            hasConfiguredAPIKey: hasConfiguredAPIKey,
            isAvailableOnCurrentOS: isAvailableOnCurrentOS,
            isLocalFluidAudioModelDownloaded: isLocalFluidAudioModelDownloaded,
            isLocalWhisperModelDownloaded: isLocalWhisperModelDownloaded,
            isLocalQwenModelDownloaded: isLocalQwenModelDownloaded
        )
    }

    var transcriptionLanguageOptions: [String: String] {
        coreFacts.transcriptionLanguageOptions
    }

    var transcriptionLanguageSelectionFacts: RomaTranscriptionLanguageSelectionFacts {
        coreFacts.transcriptionLanguageSelectionFacts
    }

    func validTranscriptionLanguageOrFallback(_ language: String?) -> String {
        coreFacts.validTranscriptionLanguageOrFallback(language)
    }

    var powerModeTranscriptionModelFacts: RomaPowerModeTranscriptionModelFacts {
        coreFacts.powerModeTranscriptionModelFacts
    }

    var powerModeTranscriptionModelResourceFacts: RomaPowerModeTranscriptionModelResourceFacts {
        coreFacts.powerModeTranscriptionModelResourceFacts
    }

    func modelManagementFacts(isAvailableOnCurrentOS: Bool) -> RomaModelManagementModelFacts {
        coreFacts.modelManagementFacts(isAvailableOnCurrentOS: isAvailableOnCurrentOS)
    }
}

// A new struct for Apple's native models
struct NativeAppleModel: TranscriptionModel {
    let id = UUID()
    let name: String
    let displayName: String
    let description: String
    let provider: RomaMacOSTranscriptionModelProvider = .nativeApple
    let isMultilingualModel: Bool
    let supportedLanguages: [String: String]

    init(spec: RomaNativeAppleTranscriptionModelSpec) {
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
    let provider: RomaMacOSTranscriptionModelProvider = .fluidAudio
    let size: String
    let speed: Double
    let accuracy: Double
    let ramUsage: Double
    let supportsStreaming: Bool
    let isMultilingualModel: Bool
    let supportedLanguages: [String: String]

    init(spec: RomaFluidAudioTranscriptionModelSpec) {
        self.name = spec.name
        self.displayName = spec.displayName
        self.description = spec.description
        self.size = spec.size
        self.speed = spec.speed
        self.accuracy = spec.accuracy
        self.ramUsage = spec.ramUsage
        self.supportsStreaming = spec.supportsStreaming
        self.isMultilingualModel = spec.isMultilingual
        self.supportedLanguages = spec.supportedLanguages
    }
}

// A new struct for cloud models
struct CloudModel: TranscriptionModel {
    let id: UUID
    let name: String
    let displayName: String
    let description: String
    let provider: RomaMacOSTranscriptionModelProvider
    let speed: Double
    let accuracy: Double
    let isMultilingualModel: Bool
    let supportsStreaming: Bool
    let supportedLanguages: [String: String]

    init(spec: RomaCloudTranscriptionModelSpec, provider: RomaMacOSTranscriptionModelProvider) {
        self.id = UUID()
        self.name = spec.name
        self.displayName = spec.displayName
        self.description = spec.description
        self.provider = provider
        self.speed = spec.speed
        self.accuracy = spec.accuracy
        self.isMultilingualModel = spec.isMultilingual
        self.supportsStreaming = spec.supportsStreaming
        self.supportedLanguages = provider.supportedLanguages(isMultilingual: spec.isMultilingual)
    }
}

/// Custom cloud model with API key stored in Keychain.
struct CustomCloudModel: TranscriptionModel, Codable {
    let id: UUID
    let name: String
    let displayName: String
    let description: String
    let provider: RomaMacOSTranscriptionModelProvider = .custom
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
        self.supportedLanguages = supportedLanguages ?? RomaMacOSTranscriptionModelProvider.whisper.supportedLanguages(isMultilingual: isMultilingual)
    }

    init(from decoder: Decoder) throws {
        let record = try RomaCustomCloudModelStoredRecord(from: decoder)
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
        try RomaCustomCloudModelStoredRecord(
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
    let provider: RomaMacOSTranscriptionModelProvider = .whisper
    let isMultilingualModel: Bool

    init(spec: RomaWhisperModelFileSpec) {
        self.name = spec.modelName
        self.displayName = spec.displayName
        self.size = spec.size
        self.isMultilingualModel = spec.isMultilingual
        self.supportedLanguages = RomaMacOSTranscriptionModelProvider.whisper.supportedLanguages(isMultilingual: spec.isMultilingual)
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
    let provider: RomaMacOSTranscriptionModelProvider = .whisper
    let isMultilingualModel: Bool
    let supportedLanguages: [String: String]

    init(fileBaseName: String) {
        self.name = fileBaseName
        self.displayName = fileBaseName
        self.description = RomaModelManagementPresentation.importedLocalModelDescription
        self.isMultilingualModel = true
        self.supportedLanguages = RomaMacOSTranscriptionModelProvider.whisper.supportedLanguages(isMultilingual: true)
    }
}

struct QwenModel: TranscriptionModel {
    let id = UUID()
    let name = RomaTranscriptionModelCatalog.localQwenModelName
    let displayName = "Qwen Chinese + English"
    let description = "Local Chinese and English dictation with Traditional Chinese output. Requires Apple Silicon and macOS 15 or later. Downloads about 1 GB; measured memory can exceed 2 GB."
    let provider: RomaMacOSTranscriptionModelProvider = .qwen
    let isMultilingualModel = true
    let supportsStreaming = true
    let supportedLanguages = RomaTranscriptionLanguageSupport.languages(for: .qwen)
}
