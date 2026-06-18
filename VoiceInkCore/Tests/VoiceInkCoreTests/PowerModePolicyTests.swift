import Foundation
import VoiceInkCore

final class PowerModePolicyTests: XCTestCase {
    func testPowerModeTriggerConfigsPreserveStoredShapeAndIdEquality() throws {
        let id = UUID()
        let appConfig = VoiceInkPowerModeAppConfig(
            id: id,
            bundleIdentifier: "com.example.App",
            appName: "Example"
        )
        let renamedAppConfig = VoiceInkPowerModeAppConfig(
            id: id,
            bundleIdentifier: "com.example.Other",
            appName: "Other"
        )
        let urlConfig = VoiceInkPowerModeURLConfig(id: id, url: "example.com")
        let renamedURLConfig = VoiceInkPowerModeURLConfig(id: id, url: "other.example.com")

        XCTAssertEqual(appConfig, renamedAppConfig)
        XCTAssertEqual(urlConfig, renamedURLConfig)

        let appObject = try jsonObject(from: appConfig)
        XCTAssertEqual(appObject["id"] as? String, id.uuidString)
        XCTAssertEqual(appObject["bundleIdentifier"] as? String, "com.example.App")
        XCTAssertEqual(appObject["appName"] as? String, "Example")

        let urlObject = try jsonObject(from: urlConfig)
        XCTAssertEqual(urlObject["id"] as? String, id.uuidString)
        XCTAssertEqual(urlObject["url"] as? String, "example.com")
    }

    func testPowerModeTriggerConfigsAdaptToPolicyRules() {
        XCTAssertEqual(
            VoiceInkPowerModeAppConfig(
                bundleIdentifier: "com.example.App",
                appName: "Example"
            ).rule,
            VoiceInkPowerModeAppRule(bundleIdentifier: "com.example.App", appName: "Example")
        )
        XCTAssertEqual(
            VoiceInkPowerModeURLConfig(url: "example.com").rule,
            VoiceInkPowerModeWebsiteRule(url: "example.com")
        )
    }

    func testPowerModeConfigPreservesStoredShapeEqualityAndRuleAdapter() throws {
        let id = UUID()
        let config = PowerModeConfig(
            id: id,
            name: "Writing",
            emoji: "W",
            appConfigs: [
                VoiceInkPowerModeAppConfig(
                    bundleIdentifier: "com.example.App",
                    appName: "Example"
                )
            ],
            urlConfigs: [
                VoiceInkPowerModeURLConfig(url: "example.com")
            ],
            isAIEnhancementEnabled: true,
            selectedPrompt: "prompt-id",
            selectedTranscriptionModelName: "ggml-base",
            selectedLanguage: "en",
            useScreenCapture: true,
            isTextFormattingEnabled: true,
            punctuationCleanupMode: .removeAll,
            lowercaseTranscription: true,
            selectedAIProvider: "openai",
            selectedAIModel: "gpt-4o",
            autoSendKey: .commandEnter,
            isEnabled: true,
            isDefault: true
        )
        let sameIDConfig = PowerModeConfig(
            id: id,
            name: "Other",
            emoji: "O",
            isAIEnhancementEnabled: false
        )

        XCTAssertEqual(config, sameIDConfig)

        let object = try jsonObject(from: config)
        XCTAssertEqual(object["id"] as? String, id.uuidString)
        XCTAssertEqual(object["name"] as? String, "Writing")
        XCTAssertEqual(object["emoji"] as? String, "W")
        XCTAssertEqual(object["selectedPrompt"] as? String, "prompt-id")
        XCTAssertEqual(object["selectedTranscriptionModelName"] as? String, "ggml-base")
        XCTAssertEqual(object["selectedLanguage"] as? String, "en")
        XCTAssertEqual(object["punctuationCleanupMode"] as? String, PunctuationCleanupMode.removeAll.rawValue)
        XCTAssertEqual(object["removePunctuation"] as? Bool, true)
        XCTAssertEqual(object["autoSendKey"] as? String, VoiceInkAutoSendKey.commandEnter.rawValue)

        let rule = config.powerModePolicyRule
        XCTAssertEqual(rule.id, id)
        XCTAssertEqual(rule.name, "Writing")
        XCTAssertEqual(
            rule.appRules,
            [VoiceInkPowerModeAppRule(bundleIdentifier: "com.example.App", appName: "Example")]
        )
        XCTAssertEqual(rule.websiteRules, [VoiceInkPowerModeWebsiteRule(url: "example.com")])
        XCTAssertTrue(rule.isEnabled)
        XCTAssertTrue(rule.isDefault)
    }

    func testPowerModeConfigDecodesLegacyStoredKeys() throws {
        let id = UUID()
        let data = Data("""
        {
          "id": "\(id.uuidString)",
          "name": "Legacy",
          "emoji": "L",
          "appConfigs": [],
          "urlConfigs": [],
          "isAIEnhancementEnabled": false,
          "useScreenCapture": false,
          "isTextFormattingEnabled": true,
          "removePunctuation": true,
          "lowercaseTranscription": true,
          "isAutoSendEnabled": true,
          "selectedWhisperModel": "ggml-base.en"
        }
        """.utf8)

        let config = try JSONDecoder().decode(PowerModeConfig.self, from: data)

        XCTAssertEqual(config.id, id)
        XCTAssertEqual(config.name, "Legacy")
        XCTAssertEqual(config.emoji, "L")
        XCTAssertEqual(config.appConfigs, [])
        XCTAssertEqual(config.urlConfigs, [])
        XCTAssertEqual(config.punctuationCleanupMode, .removeAll)
        XCTAssertTrue(config.isTextFormattingEnabled)
        XCTAssertTrue(config.lowercaseTranscription)
        XCTAssertEqual(config.autoSendKey, .enter)
        XCTAssertEqual(config.selectedTranscriptionModelName, "ggml-base.en")
        XCTAssertTrue(config.isEnabled)
        XCTAssertFalse(config.isDefault)
    }

    func testAutoSendKeyPreservesStoredValuesPickerOrderAndLabels() {
        XCTAssertEqual(
            VoiceInkAutoSendKey.allCases,
            [.none, .enter, .shiftEnter, .commandEnter]
        )
        XCTAssertEqual(VoiceInkAutoSendKey.none.rawValue, "none")
        XCTAssertEqual(VoiceInkAutoSendKey.enter.rawValue, "enter")
        XCTAssertEqual(VoiceInkAutoSendKey.shiftEnter.rawValue, "shiftEnter")
        XCTAssertEqual(VoiceInkAutoSendKey.commandEnter.rawValue, "commandEnter")
        XCTAssertEqual(VoiceInkAutoSendKey.none.displayName, "None")
        XCTAssertEqual(VoiceInkAutoSendKey.enter.displayName, "Return (⏎)")
        XCTAssertEqual(VoiceInkAutoSendKey.shiftEnter.displayName, "Shift + Return (⇧⏎)")
        XCTAssertEqual(VoiceInkAutoSendKey.commandEnter.displayName, "Command + Return (⌘⏎)")
    }

    func testAutoSendKeyEnablementAndCodableShape() throws {
        XCTAssertFalse(VoiceInkAutoSendKey.none.isEnabled)
        XCTAssertTrue(VoiceInkAutoSendKey.enter.isEnabled)
        XCTAssertTrue(VoiceInkAutoSendKey.shiftEnter.isEnabled)
        XCTAssertTrue(VoiceInkAutoSendKey.commandEnter.isEnabled)

        let data = try JSONEncoder().encode(VoiceInkAutoSendKey.commandEnter)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"commandEnter\"")
        XCTAssertEqual(
            try JSONDecoder().decode(VoiceInkAutoSendKey.self, from: data),
            .commandEnter
        )
    }

    func testNormalizedWebsiteURLPreservesExistingMacOSCleanURLPolicy() {
        XCTAssertEqual(
            VoiceInkPowerModePolicy.normalizedWebsiteURL(" HTTP://WWW.Example.COM/path "),
            "example.com/path"
        )
        XCTAssertEqual(
            VoiceInkPowerModePolicy.normalizedWebsiteURL("https://docs.example.com"),
            "docs.example.com"
        )
    }

    func testMatchingWebsiteRuleUsesEnabledOrderAndSubstringPolicy() {
        let disabled = rule(
            name: "Disabled",
            websiteRules: [VoiceInkPowerModeWebsiteRule(url: "docs.example.com")],
            isEnabled: false
        )
        let firstEnabled = rule(
            name: "Docs",
            websiteRules: [VoiceInkPowerModeWebsiteRule(url: "example.com/docs")]
        )
        let secondEnabled = rule(
            name: "Example",
            websiteRules: [VoiceInkPowerModeWebsiteRule(url: "example.com")]
        )

        let match = VoiceInkPowerModePolicy.matchingRule(
            forWebsiteURL: "https://www.example.com/docs/new",
            in: [disabled, firstEnabled, secondEnabled]
        )

        XCTAssertEqual(match?.id, firstEnabled.id)
    }

    func testMatchingWebsiteRulePreservesEmptyRuleURLRejection() {
        let emptyWebsiteRule = rule(
            name: "Empty",
            websiteRules: [VoiceInkPowerModeWebsiteRule(url: "")]
        )

        XCTAssertNil(
            VoiceInkPowerModePolicy.matchingRule(
                forWebsiteURL: "https://example.com",
                in: [emptyWebsiteRule]
            )
        )
    }

    func testMatchingAppRuleUsesExactEnabledBundleIdentifier() {
        let disabled = rule(
            name: "Disabled",
            appRules: [VoiceInkPowerModeAppRule(bundleIdentifier: "com.example.App", appName: "App")],
            isEnabled: false
        )
        let enabled = rule(
            name: "Enabled",
            appRules: [VoiceInkPowerModeAppRule(bundleIdentifier: "com.example.App", appName: "App")]
        )

        XCTAssertEqual(
            VoiceInkPowerModePolicy.matchingRule(
                forAppBundleIdentifier: "com.example.App",
                in: [disabled, enabled]
            )?.id,
            enabled.id
        )
    }

    func testDefaultAndRulePresenceRequireEnabledRules() {
        let disabledDefault = rule(name: "Disabled", isEnabled: false, isDefault: true)
        let website = rule(
            name: "Website",
            websiteRules: [VoiceInkPowerModeWebsiteRule(url: "example.com")]
        )
        let app = rule(
            name: "App",
            appRules: [VoiceInkPowerModeAppRule(bundleIdentifier: "com.example.App", appName: "App")]
        )
        let enabledDefault = rule(name: "Default", isDefault: true)

        XCTAssertTrue(VoiceInkPowerModePolicy.hasEnabledAutomaticRules(in: [disabledDefault, app]))
        XCTAssertFalse(VoiceInkPowerModePolicy.hasEnabledAutomaticRules(in: [disabledDefault]))
        XCTAssertTrue(VoiceInkPowerModePolicy.hasEnabledWebsiteRules(in: [disabledDefault, website]))
        XCTAssertFalse(VoiceInkPowerModePolicy.hasEnabledWebsiteRules(in: [disabledDefault, app]))
        XCTAssertEqual(VoiceInkPowerModePolicy.defaultRule(in: [disabledDefault, enabledDefault])?.id, enabledDefault.id)
    }

    func testValidationRejectsBlankAndDuplicateNameWithoutNormalizingName() {
        let existing = rule(name: "Writing")
        let blankCandidate = rule(name: " ")
        let duplicateCandidate = rule(name: "Writing")
        let spacedCandidate = rule(name: " Writing ")

        XCTAssertEqual(
            VoiceInkPowerModePolicy.validateForSave(
                candidate: blankCandidate,
                mode: .add,
                existing: [existing]
            ),
            [.emptyName]
        )
        XCTAssertEqual(
            VoiceInkPowerModePolicy.validateForSave(
                candidate: duplicateCandidate,
                mode: .add,
                existing: [existing]
            ),
            [.duplicateName("Writing")]
        )
        XCTAssertEqual(
            VoiceInkPowerModePolicy.validateForSave(
                candidate: spacedCandidate,
                mode: .add,
                existing: [existing]
            ),
            []
        )
    }

    func testValidationSkipsEditedRuleAndReportsDuplicateTriggers() {
        let editedID = UUID()
        let edited = rule(id: editedID, name: "Edited")
        let existing = rule(
            name: "Existing",
            appRules: [VoiceInkPowerModeAppRule(bundleIdentifier: "com.example.App", appName: "Old Name")],
            websiteRules: [VoiceInkPowerModeWebsiteRule(url: "example.com")]
        )
        let candidate = rule(
            id: editedID,
            name: "Candidate",
            appRules: [VoiceInkPowerModeAppRule(bundleIdentifier: "com.example.App", appName: "New Name")],
            websiteRules: [VoiceInkPowerModeWebsiteRule(url: "example.com")]
        )

        XCTAssertEqual(
            VoiceInkPowerModePolicy.validateForSave(
                candidate: candidate,
                mode: .edit(editedID),
                existing: [edited, existing]
            ),
            [
                .duplicateAppTrigger("New Name", "Existing"),
                .duplicateWebsiteTrigger("example.com", "Existing")
            ]
        )
    }

    func testValidationComparesWebsiteDuplicatesByRawStoredURL() {
        let existing = rule(
            name: "Existing",
            websiteRules: [VoiceInkPowerModeWebsiteRule(url: "example.com")]
        )
        let normalizedSameCandidate = rule(
            name: "Candidate",
            websiteRules: [VoiceInkPowerModeWebsiteRule(url: "https://www.example.com")]
        )

        XCTAssertEqual(
            VoiceInkPowerModePolicy.validateForSave(
                candidate: normalizedSameCandidate,
                mode: .add,
                existing: [existing]
            ),
            []
        )
    }

    func testValidationErrorDescriptionsPreserveMacOSAlertText() {
        XCTAssertEqual(
            VoiceInkPowerModeValidationError.emptyName.localizedDescription,
            "Power mode name cannot be empty."
        )
        XCTAssertEqual(
            VoiceInkPowerModeValidationError.duplicateName("Writing").localizedDescription,
            "A power mode with the name 'Writing' already exists."
        )
        XCTAssertEqual(
            VoiceInkPowerModeValidationError.duplicateAppTrigger("Notes", "Writing").localizedDescription,
            "The app 'Notes' is already configured in the 'Writing' power mode."
        )
        XCTAssertEqual(
            VoiceInkPowerModeValidationError.duplicateWebsiteTrigger("example.com", "Writing").localizedDescription,
            "The website 'example.com' is already configured in the 'Writing' power mode."
        )
    }

    private func rule(
        id: UUID = UUID(),
        name: String,
        appRules: [VoiceInkPowerModeAppRule] = [],
        websiteRules: [VoiceInkPowerModeWebsiteRule] = [],
        isEnabled: Bool = true,
        isDefault: Bool = false
    ) -> VoiceInkPowerModeRule {
        VoiceInkPowerModeRule(
            id: id,
            name: name,
            appRules: appRules,
            websiteRules: websiteRules,
            isEnabled: isEnabled,
            isDefault: isDefault
        )
    }

    private func jsonObject<T: Encodable>(from value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
