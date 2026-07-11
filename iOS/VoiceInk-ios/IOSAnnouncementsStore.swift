import Foundation
import Combine
import VoiceInkCore

@MainActor
final class IOSAnnouncementsStore: ObservableObject {
    static let shared = IOSAnnouncementsStore()

    typealias FetchAnnouncements = () async throws -> [VoiceInkRemoteAnnouncement]

    @Published private(set) var currentAnnouncement: VoiceInkAnnouncementPresentation?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let defaults: UserDefaults
    private let now: () -> Date
    private let fetchAnnouncements: FetchAnnouncements
    private var refreshLoop: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        fetchAnnouncements: @escaping FetchAnnouncements = IOSAnnouncementsStore.fetchRemoteAnnouncements
    ) {
        self.defaults = defaults
        self.now = now
        self.fetchAnnouncements = fetchAnnouncements
    }

    func start() {
        stop(clearAnnouncement: false)
        guard VoiceInkAnnouncementPreference.isEnabled(from: defaults) else {
            currentAnnouncement = nil
            return
        }

        refreshLoop = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.nanoseconds(
                    VoiceInkAnnouncementPreference.initialFetchDelay
                ))
            } catch {
                return
            }

            while !Task.isCancelled {
                await self?.refresh()
                do {
                    try await Task.sleep(nanoseconds: Self.nanoseconds(
                        VoiceInkAnnouncementPreference.refreshInterval
                    ))
                } catch {
                    return
                }
            }
        }
    }

    func setEnabled(_ isEnabled: Bool) {
        VoiceInkAnnouncementPreference.saveIsEnabled(isEnabled, to: defaults)
        if isEnabled {
            start()
        } else {
            stop(clearAnnouncement: true)
            errorMessage = nil
        }
    }

    func stop(clearAnnouncement: Bool = true) {
        refreshLoop?.cancel()
        refreshLoop = nil
        isLoading = false
        if clearAnnouncement {
            currentAnnouncement = nil
        }
    }

    func refresh() async {
        guard VoiceInkAnnouncementPreference.isEnabled(from: defaults), !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let announcements = try await fetchAnnouncements()
            try Task.checkCancellation()
            guard VoiceInkAnnouncementPreference.isEnabled(from: defaults) else {
                currentAnnouncement = nil
                return
            }
            currentAnnouncement = VoiceInkAnnouncementPolicy.nextAnnouncement(
                from: announcements,
                dismissedIds: VoiceInkAnnouncementPreference.dismissedIds(from: defaults),
                now: now()
            )
        } catch is CancellationError {
            return
        } catch {
            guard VoiceInkAnnouncementPreference.isEnabled(from: defaults) else { return }
            errorMessage = VoiceInkAnnouncementFetchDiagnostics.failureMessage(
                errorDescription: error.localizedDescription
            )
        }
    }

    func dismissCurrentAnnouncement() {
        guard let currentAnnouncement else { return }
        let ids = VoiceInkAnnouncementPreference.dismissedIds(
            afterDismissing: currentAnnouncement.id,
            currentIds: VoiceInkAnnouncementPreference.dismissedIds(from: defaults)
        )
        VoiceInkAnnouncementPreference.saveDismissedIds(ids, to: defaults)
        self.currentAnnouncement = nil
    }

    private static func fetchRemoteAnnouncements() async throws -> [VoiceInkRemoteAnnouncement] {
        var request = URLRequest(
            url: VoiceInkAnnouncementPreference.announcementsURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: VoiceInkAnnouncementPreference.requestTimeout
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([VoiceInkRemoteAnnouncement].self, from: data)
    }

    private static func nanoseconds(_ interval: TimeInterval) -> UInt64 {
        UInt64(max(0, interval) * 1_000_000_000)
    }
}
