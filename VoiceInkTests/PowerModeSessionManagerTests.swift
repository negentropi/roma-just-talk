import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
    @Test @MainActor func recorderPowerModeSelectionUsesFrozenLipOnlyMode() async throws {
        let fixture = try RecorderPowerModeFixture(mode: .lips)
        defer { fixture.restorePreferences() }
        // Recorder controls must follow the active input, even after a settings change.
        VoiceInkLipDictationPreference.saveIsEnabled(false)

        await fixture.manager.beginSession(with: fixture.configuration)

        #expect(fixture.provider.currentTranscriptionModel?.name == "audio-A")
        #expect(fixture.provider.resourceEvents.isEmpty)
        #expect(!fixture.enhancement.isEnhancementEnabled)
        #expect(fixture.enhancement.useScreenCaptureContext)
        #expect(!VoiceInkTranscriptionCleanupPreferenceStorage.isTextFormattingEnabled())
        #expect(PunctuationCleanupMode.current() == .removeAll)
        #expect(VoiceInkTranscriptionCleanupPreferenceStorage.shouldLowercase())

        fixture.provider.currentTranscriptionModel = fixture.provider.modelB
        await fixture.manager.endSession()

        #expect(fixture.provider.currentTranscriptionModel?.name == "audio-B")
        #expect(fixture.provider.resourceEvents.isEmpty)
        #expect(fixture.enhancement.isEnhancementEnabled)
        #expect(VoiceInkTranscriptionCleanupPreferenceStorage.isTextFormattingEnabled())
        #expect(PunctuationCleanupMode.current() == .keep)
        #expect(!VoiceInkTranscriptionCleanupPreferenceStorage.shouldLowercase())
    }

    @Test @MainActor func recorderPowerModeSelectionRetainsAudioForVoiceAndCombined() async throws {
        for mode in [VoiceInkDictationMode.voice, .voiceAndLips] {
            let fixture = try RecorderPowerModeFixture(mode: mode)
            defer { fixture.restorePreferences() }
            VoiceInkLipDictationPreference.saveIsEnabled(true)
            VoiceInkLipDictationPreference.saveLipOnly(true)

            await fixture.manager.beginSession(with: fixture.configuration)
            #expect(fixture.provider.currentTranscriptionModel?.name == "audio-B")
            #expect(fixture.provider.resourceEvents == ["select:audio-B", "cleanup", "load:audio-B"])

            await fixture.manager.endSession()
            #expect(fixture.provider.currentTranscriptionModel?.name == "audio-A")
            #expect(fixture.provider.resourceEvents == [
                "select:audio-B", "cleanup", "load:audio-B",
                "select:audio-A", "cleanup", "load:audio-A"
            ])
        }
    }
}

@MainActor private final class RecorderPowerModeFixture {
    let provider: RecorderPowerModeProvider
    let manager: PowerModeSessionManager
    let enhancement: AIEnhancementService
    private let container: ModelContainer
    private let sessionDefaults: UserDefaults
    private let suiteName = "VoiceInkTests.RecorderPowerMode.\(UUID().uuidString)"
    private let savedPreferences: [(String, Any?)]

    var configuration: PowerModeConfig {
        PowerModeConfig(
            name: "Recorder selection", emoji: "", isAIEnhancementEnabled: false,
            selectedTranscriptionModelName: "audio-B", selectedLanguage: "en", useScreenCapture: true,
            isTextFormattingEnabled: false, punctuationCleanupMode: .removeAll, lowercaseTranscription: true
        )
    }

    init(mode: VoiceInkDictationMode) throws {
        let schema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        sessionDefaults = try #require(UserDefaults(suiteName: suiteName))
        let keys = [
            VoiceInkLipDictationPreference.enabledKey, VoiceInkLipDictationPreference.lipOnlyKey,
            VoiceInkUserDefaultsKey.isAIEnhancementEnabled, VoiceInkUserDefaultsKey.useScreenCaptureContext,
            VoiceInkUserDefaultsKey.selectedPromptId, VoiceInkUserDefaultsKey.customPrompts,
            VoiceInkUserDefaultsKey.selectedAIProvider,
            VoiceInkUserDefaultsKey.selectedAIProviderModel(VoiceInkAIEnhancementProviderKind.gemini.rawValue),
            VoiceInkUserDefaultsKey.isTextFormattingEnabled, VoiceInkUserDefaultsKey.lowercaseTranscription,
            VoiceInkUserDefaultsKey.selectedTranscriptionLanguage, VoiceInkUserDefaultsKey.transcriptionPrompt,
            PunctuationCleanupMode.userDefaultsKey, PunctuationCleanupMode.legacyRemovePunctuationKey
        ]
        savedPreferences = keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        VoiceInkAIEnhancementProviderPreference.saveSelectedProvider(.gemini)
        VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("en")
        VoiceInkTranscriptionCleanupPreferenceStorage.saveTextFormattingEnabled(true)
        VoiceInkTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription(false)
        PunctuationCleanupMode.setCurrent(.keep)
        enhancement = AIEnhancementService(modelContext: container.mainContext)
        enhancement.isEnhancementEnabled = true
        provider = RecorderPowerModeProvider(mode: mode)
        manager = PowerModeSessionManager(defaults: sessionDefaults)
        manager.configure(engine: provider, enhancementService: enhancement)
    }

    func restorePreferences() {
        sessionDefaults.removePersistentDomain(forName: suiteName)
        for (key, value) in savedPreferences {
            if let value { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }
}

@MainActor private final class RecorderPowerModeProvider: PowerModeStateProvider {
    let currentDictationMode: VoiceInkDictationMode
    let modelA = ImportedWhisperModel(fileBaseName: "audio-A")
    let modelB = ImportedWhisperModel(fileBaseName: "audio-B")
    var currentTranscriptionModel: (any TranscriptionModel)?
    var resourceEvents: [String] = []

    init(mode: VoiceInkDictationMode) {
        currentDictationMode = mode
        currentTranscriptionModel = modelA
    }

    var allAvailableModels: [any TranscriptionModel] { [modelA, modelB] }
    var availableModels: [VoiceInkWhisperLocalModelFile] {
        [modelA, modelB].map {
            VoiceInkWhisperLocalModelFile(name: $0.name, url: URL(fileURLWithPath: "/unused-test-models/\($0.name).bin"))
        }
    }

    func setDefaultTranscriptionModel(_ model: any TranscriptionModel) {
        currentTranscriptionModel = model
        resourceEvents.append("select:\(model.name)")
    }

    func cleanupModelResources() async { resourceEvents.append("cleanup") }
    func loadModel(_ model: VoiceInkWhisperLocalModelFile) async throws { resourceEvents.append("load:\(model.name)") }
}
