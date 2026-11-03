import Foundation
import VoiceInkCore

final class PowerModeLipDictationTests: XCTestCase {
    func testLipOnlyAppliesTextPreferencesWithoutSelectingOrLoadingAudioModel() async {
        let runtime = PowerModeLipRuntime(currentModelName: "audio-A")
        let promptID = UUID()
        let config = configuration(promptID: promptID)

        await runtime.apply(.applying(
            config: config,
            facts: runtime.facts,
            applicationScope: .init(dictationMode: .lips)
        ))

        XCTAssertEqual(runtime.currentModelName, "audio-A")
        XCTAssertEqual(runtime.resourceEvents, [])
        XCTAssertEqual(runtime.enhancementEnabled, true)
        XCTAssertEqual(runtime.screenContextEnabled, true)
        XCTAssertEqual(runtime.promptID, promptID)
        XCTAssertEqual(runtime.aiProvider, .groq)
        XCTAssertEqual(runtime.aiModel, "llama-3.3")
        XCTAssertEqual(runtime.formattingEnabled, false)
        XCTAssertEqual(runtime.punctuationMode, .removeAll)
        XCTAssertEqual(runtime.lowercase, true)
        XCTAssertEqual(runtime.language, "fr")
        XCTAssertEqual(runtime.configurationNotifications, 1)

        // A model changed elsewhere must not be restored by the camera-only session.
        runtime.currentModelName = "audio-B"
        await runtime.apply(.restoring(
            state: originalState,
            facts: runtime.facts,
            applicationScope: .init(dictationMode: .lips)
        ))

        XCTAssertEqual(runtime.currentModelName, "audio-B")
        XCTAssertEqual(runtime.resourceEvents, [])
        XCTAssertEqual(runtime.enhancementEnabled, false)
        XCTAssertEqual(runtime.formattingEnabled, true)
        XCTAssertEqual(runtime.punctuationMode, .keep)
        XCTAssertEqual(runtime.lowercase, false)
        XCTAssertEqual(runtime.configurationNotifications, 1)
    }

    func testVoiceCombinedAndManualPowerModeKeepAudioModelApplicationAndRestoration() async {
        for mode in [VoiceInkDictationMode.voice, .voiceAndLips] {
            let runtime = PowerModeLipRuntime(currentModelName: "audio-A")
            let scope = VoiceInkPowerModeSessionApplicationScope(dictationMode: mode)
            await runtime.apply(.applying(config: configuration(), facts: runtime.facts, applicationScope: scope))
            XCTAssertEqual(runtime.currentModelName, "audio-B")
            XCTAssertEqual(runtime.resourceEvents, ["select:audio-B", "cleanup", "load:audio-B"])
            await runtime.apply(.restoring(state: originalState, facts: runtime.facts, applicationScope: scope))
            XCTAssertEqual(runtime.currentModelName, "audio-A")
            XCTAssertEqual(runtime.resourceEvents, ["select:audio-B", "cleanup", "load:audio-B", "select:audio-A", "cleanup", "load:audio-A"])
        }

        let manual = PowerModeLipRuntime(currentModelName: "audio-A")
        await manual.apply(.applying(config: configuration(), facts: manual.facts))
        XCTAssertEqual(manual.currentModelName, "audio-B")
        XCTAssertEqual(manual.resourceEvents, ["select:audio-B", "cleanup", "load:audio-B"])
        await manual.apply(.restoring(state: originalState, facts: manual.facts))
        XCTAssertEqual(manual.currentModelName, "audio-A")
        XCTAssertEqual(manual.resourceEvents, ["select:audio-B", "cleanup", "load:audio-B", "select:audio-A", "cleanup", "load:audio-A"])
    }

    func testReusedAndRecoveredLipSessionRetainsTextOnlyRestoration() async throws {
        let existing = VoiceInkPowerModeSession(
            id: UUID(), startTime: Date(), originalState: originalState, applicationScope: .textOnly
        )
        var session = existing
        VoiceInkPowerModeSessionBeginPlan.plan(activeSession: existing, applicationScope: .textOnly).applyRuntimeState(
            id: UUID(), startTime: Date(), originalState: originalState,
            saveSession: { session = $0 },
            installSettingsObserver: { XCTFail("An existing session already has its settings observer") }
        )
        XCTAssertEqual(session.id, existing.id)
        XCTAssertEqual(session.originalState, existing.originalState)

        VoiceInkPowerModeSessionSnapshotPlan.plan(
            isApplyingPowerModeConfiguration: false, activeSession: session
        ).applyRuntimeState(currentState: originalState, saveSession: { session = $0 })
        let recovered = try JSONDecoder().decode(VoiceInkPowerModeSession.self, from: JSONEncoder().encode(session))
        let runtime = PowerModeLipRuntime(currentModelName: "audio-B")
        await runtime.apply(.restoring(
            state: recovered.originalState, facts: runtime.facts, applicationScope: recovered.applicationScope
        ))
        XCTAssertEqual(runtime.currentModelName, "audio-B")
        XCTAssertEqual(runtime.resourceEvents, [])
        XCTAssertEqual(runtime.enhancementEnabled, false)
        XCTAssertEqual(runtime.formattingEnabled, true)

        // A persisted voice session can later serve lips, but still owes its original audio selection.
        for initialScope in [VoiceInkPowerModeSessionApplicationScope.full, .textOnly] {
            var mixed = VoiceInkPowerModeSession(
                id: UUID(), startTime: Date(), originalState: originalState, applicationScope: initialScope
            )
            for scope in [VoiceInkPowerModeSessionApplicationScope.full, .textOnly] {
                VoiceInkPowerModeSessionBeginPlan.plan(activeSession: mixed, applicationScope: scope).applyRuntimeState(
                    id: UUID(), startTime: Date(), originalState: originalState,
                    saveSession: { mixed = $0 },
                    installSettingsObserver: { XCTFail("Reusing a session must retain its observer") }
                )
            }
            await VoiceInkPowerModeRecordingFinishPlan.finishingRecording(
                shouldPersistConfiguredPreferences: true
            ).applyRuntimeState(
                endSession: { XCTFail("Persistent preferences keep the session for the next capture") },
                clearActiveConfiguration: { XCTFail("Persistent preferences keep the active configuration") }
            )
            let recoveredMixed = try JSONDecoder().decode(
                VoiceInkPowerModeSession.self, from: JSONEncoder().encode(mixed)
            )
            XCTAssertEqual(recoveredMixed.applicationScope, .full)
            XCTAssertEqual(recoveredMixed.originalState.transcriptionModelName, "audio-A")

            for loadsResources in [false, true] {
                let restored = PowerModeLipRuntime(currentModelName: "audio-B")
                await restored.apply(.restoring(
                    state: recoveredMixed.originalState, facts: restored.facts,
                    applicationScope: recoveredMixed.applicationScope, loadsModelResources: loadsResources
                ))
                XCTAssertEqual(restored.currentModelName, "audio-A")
                XCTAssertEqual(restored.resourceEvents, loadsResources
                    ? ["select:audio-A", "cleanup", "load:audio-A"] : ["select:audio-A"])
            }
        }
    }

    func testLegacySavedSessionRestoresAudioModel() async throws {
        let session = VoiceInkPowerModeSession(id: UUID(), startTime: Date(), originalState: originalState)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
        object.removeValue(forKey: "applicationScope")
        let recovered = try JSONDecoder().decode(VoiceInkPowerModeSession.self, from: JSONSerialization.data(withJSONObject: object))
        let runtime = PowerModeLipRuntime(currentModelName: "audio-B")
        await runtime.apply(.restoring(
            state: recovered.originalState, facts: runtime.facts, applicationScope: recovered.applicationScope
        ))
        XCTAssertEqual(runtime.currentModelName, "audio-A")
        XCTAssertEqual(runtime.resourceEvents, ["select:audio-A", "cleanup", "load:audio-A"])
    }

    private func configuration(promptID: UUID = UUID()) -> PowerModeConfig {
        PowerModeConfig(
            name: "Camera text", emoji: "C", isAIEnhancementEnabled: true,
            selectedPrompt: promptID.uuidString, selectedTranscriptionModelName: "audio-B",
            selectedLanguage: "fr", useScreenCapture: true, isTextFormattingEnabled: false,
            punctuationCleanupMode: .removeAll, lowercaseTranscription: true,
            selectedAIProvider: "GROQ", selectedAIModel: "llama-3.3"
        )
    }

    private var originalState: VoiceInkPowerModeApplicationState {
        VoiceInkPowerModeApplicationState(
            isEnhancementEnabled: false, useScreenCaptureContext: false,
            selectedLanguage: "en", transcriptionModelName: "audio-A", isTextFormattingEnabled: true,
            punctuationCleanupMode: .keep, lowercaseTranscription: false
        )
    }
}

private final class PowerModeLipRuntime {
    var currentModelName: String
    var resourceEvents: [String] = []
    var enhancementEnabled: Bool?
    var screenContextEnabled: Bool?
    var promptID: UUID?
    var aiProvider: VoiceInkAIEnhancementProviderKind?
    var aiModel: String?
    var formattingEnabled: Bool?
    var punctuationMode: PunctuationCleanupMode?
    var lowercase: Bool?
    var language: String?
    var configurationNotifications = 0

    init(currentModelName: String) { self.currentModelName = currentModelName }

    var facts: VoiceInkPowerModeSessionApplicationFacts {
        VoiceInkPowerModeSessionApplicationFacts(
            currentModelName: currentModelName,
            availableModelResourceFacts: ["audio-A", "audio-B"].map {
                VoiceInkPowerModeTranscriptionModelResourceFacts(name: $0, loadsLocalWhisperModel: true)
            },
            availableLocalModelNames: ["audio-A", "audio-B"]
        )
    }

    func apply(_ plan: VoiceInkPowerModeSessionApplicationPlan) async {
        await plan.applyRuntimeState(
            applyPreferenceApplication: { application in
                application.applyRuntimeState(
                    setEnhancementEnabled: { self.enhancementEnabled = $0 },
                    setUseScreenCaptureContext: { self.screenContextEnabled = $0 },
                    setSelectedPromptId: { self.promptID = $0 },
                    setSelectedAIProvider: { self.aiProvider = $0 },
                    selectAIModel: { self.aiModel = $0 },
                    saveTextFormattingEnabled: { self.formattingEnabled = $0 },
                    setPunctuationCleanupMode: { self.punctuationMode = $0 },
                    saveLowercaseTranscription: { self.lowercase = $0 }
                )
            },
            applyModelResourcePlan: { resources in
                await resources.applyRuntimeState(
                    setDefaultTranscriptionModelNamed: { name in
                        self.currentModelName = name
                        self.resourceEvents.append("select:\(name)")
                        return true
                    },
                    cleanupModelResources: { self.resourceEvents.append("cleanup") },
                    loadDownloadedLocalModelNamed: { self.resourceEvents.append("load:\($0)") },
                    handleLocalModelLoadFailure: { _, _ in XCTFail("Fixture model load failed") }
                )
            },
            applyLanguageApplicationPlan: { language in
                language.applyRuntimeState(saveSelectedLanguage: { self.language = $0 }, postLanguageDidChange: {})
            },
            postConfigurationApplied: { self.configurationNotifications += 1 }
        )
    }
}
