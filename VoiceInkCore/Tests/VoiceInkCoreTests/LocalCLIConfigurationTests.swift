import Foundation
@testable import VoiceInkCore

final class LocalCLIConfigurationTests: XCTestCase {
    func testLocalCLITemplatesPreserveRawValuesDisplayNamesAndCommands() {
        XCTAssertEqual(VoiceInkLocalCLITemplate.allCases, [.pi, .claude, .codex, .copilot])
        XCTAssertEqual(VoiceInkLocalCLITemplate.pi.rawValue, "pi")
        XCTAssertEqual(VoiceInkLocalCLITemplate.claude.rawValue, "claude")
        XCTAssertEqual(VoiceInkLocalCLITemplate.codex.rawValue, "codex")
        XCTAssertEqual(VoiceInkLocalCLITemplate.copilot.rawValue, "copilot")

        XCTAssertEqual(VoiceInkLocalCLITemplate.pi.displayName, "Pi")
        XCTAssertEqual(VoiceInkLocalCLITemplate.claude.displayName, "Claude")
        XCTAssertEqual(VoiceInkLocalCLITemplate.codex.displayName, "Codex")
        XCTAssertEqual(VoiceInkLocalCLITemplate.copilot.displayName, "Copilot")

        XCTAssertEqual(
            VoiceInkLocalCLITemplate.pi.commandTemplate,
            "pi -ne -ns -p --no-tools --system-prompt \"$VOICEINK_SYSTEM_PROMPT\" \"$VOICEINK_USER_PROMPT\""
        )
        XCTAssertEqual(VoiceInkLocalCLITemplate.claude.commandTemplate, "claude -p \"$VOICEINK_FULL_PROMPT\"")
        XCTAssertEqual(
            VoiceInkLocalCLITemplate.codex.commandTemplate,
            "TMPFILE=$(mktemp) && codex exec --skip-git-repo-check --output-last-message \"$TMPFILE\" \"$VOICEINK_FULL_PROMPT\" > /dev/null 2>&1 && cat \"$TMPFILE\" && rm \"$TMPFILE\""
        )
        XCTAssertEqual(
            VoiceInkLocalCLITemplate.copilot.commandTemplate,
            "copilot -p \"$VOICEINK_FULL_PROMPT\" -s --no-ask-user --available-tools=__none__ 2>/dev/null"
        )
    }

    func testLocalCLIPreferencePreservesKeysDefaultsAndRoundTrips() {
        XCTAssertEqual(VoiceInkLocalCLIPreference.commandTemplateKey, "localCLICommandTemplate")
        XCTAssertEqual(VoiceInkLocalCLIPreference.selectedTemplateKey, "localCLISelectedTemplate")
        XCTAssertEqual(VoiceInkLocalCLIPreference.timeoutSecondsKey, "localCLITimeoutSeconds")
        XCTAssertEqual(VoiceInkLocalCLIPreference.defaultTimeoutSeconds, 45)
        XCTAssertEqual(VoiceInkLocalCLIPreference.minimumTimeoutSeconds, 5)
        XCTAssertEqual(VoiceInkLocalCLIPreference.timeoutOptions, [15, 30, 45, 60, 90, 120, 180, 300])

        withIsolatedDefaults { defaults in
            XCTAssertEqual(VoiceInkLocalCLIPreference.commandTemplate(from: defaults), "")
            XCTAssertEqual(VoiceInkLocalCLIPreference.selectedTemplate(from: defaults), .pi)
            XCTAssertEqual(VoiceInkLocalCLIPreference.timeoutSeconds(from: defaults), 45)

            defaults.set(3, forKey: VoiceInkLocalCLIPreference.timeoutSecondsKey)
            XCTAssertEqual(VoiceInkLocalCLIPreference.timeoutSeconds(from: defaults), 3)

            VoiceInkLocalCLIPreference.saveCommandTemplate("codex exec \"$VOICEINK_FULL_PROMPT\"", to: defaults)
            VoiceInkLocalCLIPreference.saveSelectedTemplate(.codex, to: defaults)
            VoiceInkLocalCLIPreference.saveTimeoutSeconds(3, to: defaults)

            XCTAssertEqual(
                VoiceInkLocalCLIPreference.commandTemplate(from: defaults),
                "codex exec \"$VOICEINK_FULL_PROMPT\""
            )
            XCTAssertEqual(VoiceInkLocalCLIPreference.selectedTemplate(from: defaults), .codex)
            XCTAssertEqual(VoiceInkLocalCLIPreference.timeoutSeconds(from: defaults), 5)

            VoiceInkLocalCLIPreference.saveTimeoutSeconds(90, to: defaults)
            XCTAssertEqual(VoiceInkLocalCLIPreference.timeoutSeconds(from: defaults), 90)

            VoiceInkLocalCLIPreference.clear(from: defaults)
            XCTAssertEqual(VoiceInkLocalCLIPreference.commandTemplate(from: defaults), "")
            XCTAssertEqual(VoiceInkLocalCLIPreference.selectedTemplate(from: defaults), .pi)
            XCTAssertEqual(VoiceInkLocalCLIPreference.timeoutSeconds(from: defaults), 45)
        }
    }

    func testLocalCLICommandConfigurationAndPromptPolicy() {
        XCTAssertFalse(VoiceInkLocalCLIPreference.isCommandConfigured(""))
        XCTAssertFalse(VoiceInkLocalCLIPreference.isCommandConfigured(" \n\t "))
        XCTAssertTrue(VoiceInkLocalCLIPreference.isCommandConfigured("pi \"$VOICEINK_FULL_PROMPT\""))
        XCTAssertEqual(VoiceInkLocalCLIPreference.boundedTimeoutSeconds(1), 5)
        XCTAssertEqual(VoiceInkLocalCLIPreference.boundedTimeoutSeconds(30), 30)
        XCTAssertEqual(VoiceInkLocalCLIPreference.timeoutLabel(for: 120), "120s")

        XCTAssertEqual(
            VoiceInkLocalCLIPreference.fullPrompt(systemPrompt: "System", userPrompt: "User"),
            """
            <SYSTEM_PROMPT>
            System
            </SYSTEM_PROMPT>

            <USER_PROMPT>
            User
            </USER_PROMPT>
            """
        )
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.LocalCLIConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        run(defaults)
    }
}
