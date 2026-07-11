import XCTest
import VoiceInkCore
@testable import VoiceInk_ios

@MainActor
final class IOSAnnouncementsStoreTests: XCTestCase {
    func testRefreshSelectsActiveUndismissedAnnouncement() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = IOSAnnouncementsStore(
            defaults: defaults,
            now: { now },
            fetchAnnouncements: {
                [VoiceInkRemoteAnnouncement(
                    id: "active",
                    title: "Active",
                    description: "Details",
                    url: "https://example.com",
                    startAt: nil,
                    endAt: nil
                )]
            }
        )

        await store.refresh()

        XCTAssertEqual(store.currentAnnouncement?.id, "active")
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isLoading)
    }

    func testDismissPersistsAndSuppressesAnnouncement() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let announcement = VoiceInkRemoteAnnouncement(
            id: "dismissed",
            title: "Dismissed",
            description: nil,
            url: nil,
            startAt: nil,
            endAt: nil
        )
        let store = IOSAnnouncementsStore(
            defaults: defaults,
            fetchAnnouncements: { [announcement] }
        )

        await store.refresh()
        store.dismissCurrentAnnouncement()
        await store.refresh()

        XCTAssertNil(store.currentAnnouncement)
        XCTAssertEqual(VoiceInkAnnouncementPreference.dismissedIds(from: defaults), ["dismissed"])
    }

    func testRefreshExposesFailureAndRetryCanRecover() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var shouldFail = true
        let store = IOSAnnouncementsStore(
            defaults: defaults,
            fetchAnnouncements: {
                if shouldFail {
                    throw URLError(.notConnectedToInternet)
                }
                return []
            }
        )

        await store.refresh()
        XCTAssertNotNil(store.errorMessage)

        shouldFail = false
        await store.refresh()

        XCTAssertNil(store.errorMessage)
        XCTAssertNil(store.currentAnnouncement)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "VoiceInkIOSAnnouncementsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.register(defaults: VoiceInkAnnouncementPreference.registeredDefaults)
        return (defaults, suiteName)
    }
}
