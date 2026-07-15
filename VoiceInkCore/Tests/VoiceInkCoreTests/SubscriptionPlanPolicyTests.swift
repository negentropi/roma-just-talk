@testable import VoiceInkCore

final class SubscriptionPlanPolicyTests: XCTestCase {
    func testCatalogPreservesFreemiumItalyAndRomaOffer() {
        XCTAssertEqual(VoiceInkSubscriptionCatalog.freemium.weeklyWordLimit, 4_760)
        XCTAssertEqual(VoiceInkSubscriptionCatalog.italy.monthlyPriceUSD, 8)
        XCTAssertEqual(VoiceInkSubscriptionCatalog.roma.monthlyPriceUSD, 15)
        XCTAssertEqual(VoiceInkSubscriptionCatalog.plans.map(\.id), [.freemium, .italy, .roma])
        XCTAssertTrue(VoiceInkSubscriptionCatalog.italy.hasUnlimitedAppUsage)
        XCTAssertTrue(VoiceInkSubscriptionCatalog.roma.hasUnlimitedAppUsage)
    }

    func testWeeklyAllowanceClampsUsageAndBlocksOnlyAtFreemiumLimit() {
        XCTAssertEqual(
            VoiceInkWeeklyWordAllowance(plan: VoiceInkSubscriptionCatalog.freemium, used: -1).remaining,
            4_760
        )
        XCTAssertEqual(
            VoiceInkWeeklyWordAllowance(plan: VoiceInkSubscriptionCatalog.freemium, used: 4_759).remaining,
            1
        )
        XCTAssertFalse(
            VoiceInkWeeklyWordAllowance(plan: VoiceInkSubscriptionCatalog.freemium, used: 4_760)
                .canStartTranscription
        )
        XCTAssertTrue(
            VoiceInkWeeklyWordAllowance(plan: VoiceInkSubscriptionCatalog.italy, used: 50_000)
                .canStartTranscription
        )
    }

    func testFreemiumLearnMoreExplains476Reference() {
        XCTAssertEqual(VoiceInkSubscriptionCatalog.freemiumLearnMoreTitle, "Why 4,760 words?")
        XCTAssertTrue(VoiceInkSubscriptionCatalog.freemiumLearnMoreText.contains("476 CE"))
    }
}
