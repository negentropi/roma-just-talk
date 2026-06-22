import Foundation
import VoiceInkCore

/// A minimal pull-based announcements fetcher that shows one-time in-app banners.
final class AnnouncementsService {
    static let shared = AnnouncementsService()

    private init() {}

    // MARK: - Configuration

    private var timer: Timer?

    // MARK: - Public API

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: VoiceInkAnnouncementPreference.refreshInterval, repeats: true) { [weak self] _ in
            self?.fetchAndMaybeShow()
        }
        // Do an initial fetch shortly after launch
        DispatchQueue.main.asyncAfter(deadline: .now() + VoiceInkAnnouncementPreference.initialFetchDelay) { [weak self] in
            self?.fetchAndMaybeShow()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Core Logic

    private func fetchAndMaybeShow() {
        let request = URLRequest(
            url: VoiceInkAnnouncementPreference.announcementsURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: VoiceInkAnnouncementPreference.requestTimeout
        )
        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            guard error == nil, let data = data else { return }
            guard let announcements = try? JSONDecoder().decode([VoiceInkRemoteAnnouncement].self, from: data) else { return }
            guard let next = VoiceInkAnnouncementPolicy.nextAnnouncement(
                from: announcements,
                dismissedIds: VoiceInkAnnouncementPreference.dismissedIds(),
                now: Date()
            ) else { return }

            DispatchQueue.main.async {
                AnnouncementManager.shared.showAnnouncement(
                    presentation: next,
                    onDismiss: {
                        let ids = VoiceInkAnnouncementPreference.dismissedIds(
                            afterDismissing: next.id,
                            currentIds: VoiceInkAnnouncementPreference.dismissedIds()
                        )
                        VoiceInkAnnouncementPreference.saveDismissedIds(ids)
                    }
                )
            }
        }
        task.resume()
    }
}
