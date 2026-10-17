@testable import RomaCore

final class SubscriptionPlanPolicyTests: XCTestCase {
    func testCatalogPreservesFreemiumItalyAndRomaOffer() {
        XCTAssertEqual(RomaSubscriptionCatalog.freemium.weeklyWordLimit, 4_760)
        XCTAssertEqual(RomaSubscriptionCatalog.italy.monthlyPriceUSD, 8)
        XCTAssertEqual(RomaSubscriptionCatalog.roma.monthlyPriceUSD, 15)
        XCTAssertEqual(RomaSubscriptionCatalog.plans.map(\.id), [.freemium, .italy, .roma])
        XCTAssertTrue(RomaSubscriptionCatalog.italy.hasUnlimitedAppUsage)
        XCTAssertTrue(RomaSubscriptionCatalog.roma.hasUnlimitedAppUsage)
    }

    func testWeeklyAllowanceClampsUsageAndBlocksOnlyAtFreemiumLimit() {
        XCTAssertEqual(
            RomaWeeklyWordAllowance(plan: RomaSubscriptionCatalog.freemium, used: -1).remaining,
            4_760
        )
        XCTAssertEqual(
            RomaWeeklyWordAllowance(plan: RomaSubscriptionCatalog.freemium, used: 4_759).remaining,
            1
        )
        XCTAssertFalse(
            RomaWeeklyWordAllowance(plan: RomaSubscriptionCatalog.freemium, used: 4_760)
                .canStartTranscription
        )
        XCTAssertTrue(
            RomaWeeklyWordAllowance(plan: RomaSubscriptionCatalog.italy, used: 50_000)
                .canStartTranscription
        )
    }

    func testFreemiumLearnMoreExplains476Reference() {
        XCTAssertEqual(RomaSubscriptionCatalog.freemiumLearnMoreTitle, "Why 4,760 words?")
        XCTAssertTrue(RomaSubscriptionCatalog.freemiumLearnMoreText.contains("476 CE"))
    }
}
