import Testing
import VoiceInkCore
@testable import VoiceInk

@Suite(.serialized)
struct PowerModeConfigTests {
    @Test func automaticRuleDetectionIgnoresDisabledRules() {
        let disabledURL = powerModeConfig(
            urlConfigs: [VoiceInkPowerModeURLConfig(url: "example.com")],
            isEnabled: false
        )

        #expect(![disabledURL].hasEnabledAutomaticRules)
        #expect(![disabledURL].hasEnabledURLRules)
    }

    @Test func automaticRuleDetectionSeparatesURLRulesFromAppAndDefaultRules() {
        let appRule = powerModeConfig(
            appConfigs: [VoiceInkPowerModeAppConfig(bundleIdentifier: "com.apple.TextEdit", appName: "TextEdit")]
        )
        let defaultRule = powerModeConfig(isDefault: true)
        let urlRule = powerModeConfig(urlConfigs: [VoiceInkPowerModeURLConfig(url: "example.com")])

        #expect([appRule].hasEnabledAutomaticRules)
        #expect(![appRule].hasEnabledURLRules)
        #expect([defaultRule].hasEnabledAutomaticRules)
        #expect(![defaultRule].hasEnabledURLRules)
        #expect([urlRule].hasEnabledAutomaticRules)
        #expect([urlRule].hasEnabledURLRules)
    }

    private func powerModeConfig(
        appConfigs: [VoiceInkPowerModeAppConfig]? = nil,
        urlConfigs: [VoiceInkPowerModeURLConfig]? = nil,
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
