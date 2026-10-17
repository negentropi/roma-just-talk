import XCTest
import RomaCore
@testable import roma_just_talk

final class IOSPromptLibraryTests: XCTestCase {
    func testModePromptSelectionRoundTripsAndBuildsNamedRuntimePrompt() throws {
        let prompt = RomaCustomPrompt(
            title: "Email",
            promptText: "Write an email",
            useSystemInstructions: false
        )
        var mode = Mode(
            name: "Writing",
            transcriptionProvider: .localWhisper,
            isPostProcessingEnabled: true,
            postProcessingProvider: .groq
        )
        mode.selectedPromptId = prompt.id

        let decoded = try JSONDecoder().decode(
            Mode.self,
            from: JSONEncoder().encode(mode)
        )
        let configuration = decoded.runtimeConfiguration(
            additionalLocalWhisperModelNames: [],
            prompts: [prompt]
        )

        XCTAssertEqual(decoded.selectedPromptId, prompt.id)
        XCTAssertEqual(configuration.prompt, "Write an email")
        XCTAssertEqual(configuration.promptName, "Email")
    }

    func testRecordingPromptOverrideWinsOverModePrompt() {
        let modePrompt = RomaCustomPrompt(
            title: "Mode",
            promptText: "Mode prompt",
            useSystemInstructions: false
        )
        let recordingPrompt = RomaCustomPrompt(
            title: "Recording",
            promptText: "Recording prompt",
            useSystemInstructions: false
        )
        var mode = Mode(
            name: "Writing",
            transcriptionProvider: .localWhisper,
            isPostProcessingEnabled: true,
            postProcessingProvider: .groq
        )
        mode.selectedPromptId = modePrompt.id

        let snapshot = RomaIOSAppSettingsRunSnapshot(
            modes: [mode],
            selectedModeId: mode.id,
            selectedTranscriptionLanguage: "en",
            wordReplacementRules: [],
            customVocabulary: [],
            promptLibrary: [modePrompt, recordingPrompt],
            recordingPromptOverrideId: recordingPrompt.id
        )
        let settings = snapshot.transcriptionRunSettings()

        XCTAssertEqual(settings.selectedPromptId, recordingPrompt.id)
        XCTAssertEqual(settings.configuration.prompt, "Recording prompt")
        XCTAssertEqual(settings.configuration.promptName, "Recording")
    }

    func testPromptStoragePreservesUserOrderAndTriggerWords() throws {
        let suiteName = "IOSPromptLibraryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let prompts = [
            RomaCustomPrompt(title: "Email", promptText: "Email", triggerWords: ["email"]),
            RomaCustomPrompt(title: "Summary", promptText: "Summary", triggerWords: ["summary"])
        ]

        RomaCustomPromptStorage.savePrompts(prompts, to: defaults)

        XCTAssertEqual(RomaCustomPromptStorage.loadPrompts(from: defaults), prompts)
    }
}
