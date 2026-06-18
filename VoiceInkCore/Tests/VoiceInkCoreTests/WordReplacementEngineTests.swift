import Foundation
@testable import VoiceInkCore

final class WordReplacementEngineTests: XCTestCase {
    func testSortedRulesPreferLongerOriginalText() {
        let rules = [
            VoiceInkWordReplacementRule(originalText: "voice", replacementText: "v"),
            VoiceInkWordReplacementRule(originalText: "voice ink", replacementText: "roma")
        ]

        XCTAssertEqual(
            VoiceInkWordReplacementEngine.sortedRules(rules).map(\.originalText),
            ["voice ink", "voice"]
        )
    }

    func testApplyUsesCaseInsensitiveWordBoundariesForSpacedText() {
        let rules = [
            VoiceInkWordReplacementRule(originalText: "voice ink", replacementText: "roma")
        ]

        XCTAssertEqual(
            VoiceInkWordReplacementEngine.apply(rules, to: "Use Voice Ink, not voice inking."),
            "Use roma, not voice inking."
        )
    }

    func testApplySortsCommaSeparatedVariantsByLength() {
        let rules = [
            VoiceInkWordReplacementRule(originalText: "voice, voice ink", replacementText: "roma")
        ]

        XCTAssertEqual(
            VoiceInkWordReplacementEngine.apply(rules, to: "voice ink and voice"),
            "roma and roma"
        )
    }

    func testApplyUsesSubstringReplacementForNonSpacedScripts() {
        let rules = [
            VoiceInkWordReplacementRule(originalText: "東京", replacementText: "Tokyo")
        ]

        XCTAssertEqual(
            VoiceInkWordReplacementEngine.apply(rules, to: "東京都 and 東京"),
            "Tokyo都 and Tokyo"
        )
    }

    func testRuleCodableRoundTripsIOSPreferenceShape() throws {
        let rules = [
            VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
        ]

        let data = try JSONEncoder().encode(rules)
        let decoded = try JSONDecoder().decode([VoiceInkWordReplacementRule].self, from: data)

        XCTAssertEqual(decoded, rules)
    }
}
