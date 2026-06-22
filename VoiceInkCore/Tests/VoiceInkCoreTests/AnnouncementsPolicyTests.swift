import Foundation
@testable import VoiceInkCore

final class AnnouncementsPolicyTests: XCTestCase {
    func testAnnouncementPreferencePreservesMacOSStorageAndFetchDefaults() {
        XCTAssertEqual(VoiceInkAnnouncementPreference.isEnabledKey, "enableAnnouncements")
        XCTAssertEqual(VoiceInkAnnouncementPreference.dismissedIdsKey, "dismissedAnnouncementIds")
        XCTAssertEqual(VoiceInkAnnouncementPreference.defaultIsEnabled, true)
        XCTAssertEqual(VoiceInkAnnouncementPreference.maxDismissedIdsToKeep, 2)
        XCTAssertEqual(
            VoiceInkAnnouncementPreference.announcementsURLString,
            "https://beingpax.github.io/VoiceInk/announcements.json"
        )
        XCTAssertEqual(
            VoiceInkAnnouncementPreference.announcementsURL.absoluteString,
            "https://beingpax.github.io/VoiceInk/announcements.json"
        )
        XCTAssertEqual(VoiceInkAnnouncementPreference.refreshInterval, 4 * 60 * 60)
        XCTAssertEqual(VoiceInkAnnouncementPreference.initialFetchDelay, 5)
        XCTAssertEqual(VoiceInkAnnouncementPreference.requestTimeout, 10)
        XCTAssertEqual(
            VoiceInkAnnouncementPreference.registeredDefaults[VoiceInkAnnouncementPreference.isEnabledKey] as? Bool,
            Optional(true)
        )
    }

    func testAnnouncementPreferenceReadsAndSavesEnabledFlagAndDismissedIds() {
        withTemporaryDefaults { defaults in
            XCTAssertTrue(VoiceInkAnnouncementPreference.isEnabled(from: defaults))
            XCTAssertEqual(VoiceInkAnnouncementPreference.dismissedIds(from: defaults), [])

            VoiceInkAnnouncementPreference.saveIsEnabled(false, to: defaults)
            VoiceInkAnnouncementPreference.saveDismissedIds(["one", "two"], to: defaults)

            XCTAssertFalse(VoiceInkAnnouncementPreference.isEnabled(from: defaults))
            XCTAssertEqual(VoiceInkAnnouncementPreference.dismissedIds(from: defaults), ["one", "two"])
        }
    }

    func testDismissedIdsPlanAvoidsDuplicatesAndKeepsMostRecentTwo() {
        XCTAssertEqual(
            VoiceInkAnnouncementPreference.dismissedIds(afterDismissing: "one", currentIds: ["one"]),
            ["one"]
        )
        XCTAssertEqual(
            VoiceInkAnnouncementPreference.dismissedIds(afterDismissing: "three", currentIds: ["one", "two"]),
            ["two", "three"]
        )
        XCTAssertTrue(VoiceInkAnnouncementPreference.isDismissed("two", dismissedIds: ["one", "two"]))
        XCTAssertFalse(VoiceInkAnnouncementPreference.isDismissed("three", dismissedIds: ["one", "two"]))
    }

    func testAnnouncementActiveWindowPreservesOpenEndedAndInvalidDateBehavior() throws {
        let now = try date("2026-06-21T12:00:00Z")

        XCTAssertTrue(VoiceInkAnnouncementPolicy.isActive(
            announcement(id: "current", startAt: "2026-06-21T11:00:00Z", endAt: "2026-06-21T13:00:00Z"),
            at: now
        ))
        XCTAssertFalse(VoiceInkAnnouncementPolicy.isActive(
            announcement(id: "future", startAt: "2026-06-21T13:00:00Z", endAt: nil),
            at: now
        ))
        XCTAssertFalse(VoiceInkAnnouncementPolicy.isActive(
            announcement(id: "expired", startAt: nil, endAt: "2026-06-21T11:00:00Z"),
            at: now
        ))
        XCTAssertTrue(VoiceInkAnnouncementPolicy.isActive(
            announcement(id: "invalid", startAt: "bad", endAt: "also-bad"),
            at: now
        ))
    }

    func testNextAnnouncementSkipsDismissedAndInactiveThenReturnsFirstValidPresentation() throws {
        let now = try date("2026-06-21T12:00:00Z")
        let next = VoiceInkAnnouncementPolicy.nextAnnouncement(
            from: [
                announcement(id: "dismissed"),
                announcement(id: "future", startAt: "2026-06-21T13:00:00Z", endAt: nil),
                announcement(id: "valid", description: "Body", url: "https://tryvoiceink.com/docs")
            ],
            dismissedIds: ["dismissed"],
            now: now
        )

        XCTAssertEqual(next?.id, Optional("valid"))
        XCTAssertEqual(next?.title, Optional("Title valid"))
        XCTAssertEqual(next?.description, Optional("Body"))
        XCTAssertEqual(next?.learnMoreURL, URL(string: "https://tryvoiceink.com/docs"))
    }

    func testAnnouncementPresentationPreservesMacOSActionCopyAndDescriptionVisibility() throws {
        let now = try date("2026-06-21T12:00:00Z")
        let visible = try XCTUnwrap(VoiceInkAnnouncementPolicy.nextAnnouncement(
            from: [
                announcement(id: "visible", description: " Body ", url: "https://tryvoiceink.com/docs")
            ],
            dismissedIds: [],
            now: now
        ))

        XCTAssertEqual(visible.closeButtonSystemImageName, "xmark")
        XCTAssertEqual(visible.learnMoreButtonTitle, "Learn more")
        XCTAssertEqual(visible.dismissButtonTitle, "Dismiss")
        XCTAssertEqual(visible.descriptionText, " Body ")
        XCTAssertTrue(visible.shouldShowDescription)

        let blank = try XCTUnwrap(VoiceInkAnnouncementPolicy.nextAnnouncement(
            from: [
                announcement(id: "blank", description: " \n\t ")
            ],
            dismissedIds: [],
            now: now
        ))

        XCTAssertEqual(blank.descriptionText, " \n\t ")
        XCTAssertFalse(blank.shouldShowDescription)
    }

    func testNextAnnouncementReturnsNilWhenNothingIsEligible() throws {
        let now = try date("2026-06-21T12:00:00Z")
        XCTAssertNil(VoiceInkAnnouncementPolicy.nextAnnouncement(
            from: [
                announcement(id: "dismissed"),
                announcement(id: "future", startAt: "2026-06-21T13:00:00Z", endAt: nil)
            ],
            dismissedIds: ["dismissed"],
            now: now
        ))
    }

    private func announcement(
        id: String,
        description: String? = nil,
        url: String? = nil,
        startAt: String? = nil,
        endAt: String? = nil
    ) -> VoiceInkRemoteAnnouncement {
        VoiceInkRemoteAnnouncement(
            id: id,
            title: "Title \(id)",
            description: description,
            url: url,
            startAt: startAt,
            endAt: endAt
        )
    }

    private func date(_ string: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: string))
    }

    private func withTemporaryDefaults(_ test: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.AnnouncementsPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        test(defaults)
    }
}
