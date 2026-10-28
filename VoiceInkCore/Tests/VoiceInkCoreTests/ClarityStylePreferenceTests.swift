import Foundation
@testable import VoiceInkCore

final class ClarityStylePreferenceTests: XCTestCase {
    func testMissingUnknownAndWrongTypeStylesUseNatural() {
        let name = "ClarityStylePreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        XCTAssertEqual(VoiceInkClarityStyle.current(in: defaults), .natural)
        defaults.set("future-style", forKey: VoiceInkClarityStyle.storageKey)
        XCTAssertEqual(VoiceInkClarityStyle.current(in: defaults), .natural)
        defaults.set(42, forKey: VoiceInkClarityStyle.storageKey)
        XCTAssertEqual(VoiceInkClarityStyle.current(in: defaults), .natural)
    }

    func testStyleSurvivesPreferencesReopenAndLeavesCustomSettingsIntact() {
        let name = "ClarityStylePreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: VoiceInkUserDefaultsKey.lowercaseTranscription)
        PunctuationCleanupMode.setCurrent(.removeAll, in: defaults)
        VoiceInkDictationProfile.none.save(to: defaults)

        VoiceInkClarityStyle.formal.save(to: defaults)
        let reopened = UserDefaults(suiteName: name)!
        XCTAssertEqual(VoiceInkClarityStyle.current(in: reopened), .formal)
        VoiceInkClarityStyle.casual.save(to: reopened)
        XCTAssertEqual(VoiceInkClarityStyle.current(in: defaults), .casual)
        XCTAssertEqual(VoiceInkDictationProfile.current(in: defaults), .none)
        XCTAssertTrue(defaults.bool(forKey: VoiceInkUserDefaultsKey.lowercaseTranscription))
        XCTAssertEqual(PunctuationCleanupMode.current(in: defaults), .removeAll)
    }
}
