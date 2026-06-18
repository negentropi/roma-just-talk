import Testing
@testable import VoiceInk

@Suite(.serialized)
struct PowerModeConfigTests {
    @Test func automaticRuleDetectionIgnoresDisabledRules() {
        let disabledURL = powerModeConfig(
            urlConfigs: [URLConfig(url: "example.com")],
            isEnabled: false
        )

        #expect(![disabledURL].hasEnabledAutomaticRules)
        #expect(![disabledURL].hasEnabledURLRules)
    }

    @Test func automaticRuleDetectionSeparatesURLRulesFromAppAndDefaultRules() {
        let appRule = powerModeConfig(
            appConfigs: [AppConfig(bundleIdentifier: "com.apple.TextEdit", appName: "TextEdit")]
        )
        let defaultRule = powerModeConfig(isDefault: true)
        let urlRule = powerModeConfig(urlConfigs: [URLConfig(url: "example.com")])

        #expect([appRule].hasEnabledAutomaticRules)
        #expect(![appRule].hasEnabledURLRules)
        #expect([defaultRule].hasEnabledAutomaticRules)
        #expect(![defaultRule].hasEnabledURLRules)
        #expect([urlRule].hasEnabledAutomaticRules)
        #expect([urlRule].hasEnabledURLRules)
    }

    private func powerModeConfig(
        appConfigs: [AppConfig]? = nil,
        urlConfigs: [URLConfig]? = nil,
        isEnabled: Bool = true,
        isDefault: Bool = false
    ) -> PowerModeConfig {
        PowerModeConfig(
            name: "Test",
            emoji: "T",
            appConfigs: appConfigs,
            urlConfigs: urlConfigs,
            isAIEnhancementEnabled: false,
            selectedTranscriptionModelName: nil,
            selectedLanguage: "en",
            isEnabled: isEnabled,
            isDefault: isDefault
        )
    }
}
