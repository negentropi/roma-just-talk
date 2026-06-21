import Foundation

public struct VoiceInkRemoteAnnouncement: Decodable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let description: String?
    public let url: String?
    public let startAt: String?
    public let endAt: String?

    public init(
        id: String,
        title: String,
        description: String?,
        url: String?,
        startAt: String?,
        endAt: String?
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.url = url
        self.startAt = startAt
        self.endAt = endAt
    }
}

public struct VoiceInkAnnouncementPresentation: Equatable, Sendable {
    public let id: String
    public let title: String
    public let description: String?
    public let learnMoreURL: URL?

    public init(id: String, title: String, description: String?, learnMoreURL: URL?) {
        self.id = id
        self.title = title
        self.description = description
        self.learnMoreURL = learnMoreURL
    }
}

public enum VoiceInkAnnouncementPreference {
    public static let isEnabledKey = VoiceInkUserDefaultsKey.enableAnnouncements
    public static let dismissedIdsKey = "dismissedAnnouncementIds"
    public static let defaultIsEnabled = VoiceInkPreferenceDefault.enableAnnouncements
    public static let maxDismissedIdsToKeep = 2
    public static let announcementsURLString = "https://beingpax.github.io/VoiceInk/announcements.json"
    public static let refreshInterval: TimeInterval = 4 * 60 * 60
    public static let initialFetchDelay: TimeInterval = 5
    public static let requestTimeout: TimeInterval = 10

    public static var announcementsURL: URL {
        URL(string: announcementsURLString)!
    }

    public static var registeredDefaults: [String: Any] {
        [
            isEnabledKey: defaultIsEnabled
        ]
    }

    public static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: isEnabledKey) != nil else {
            return defaultIsEnabled
        }

        return defaults.bool(forKey: isEnabledKey)
    }

    public static func saveIsEnabled(_ isEnabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: isEnabledKey)
    }

    public static func dismissedIds(from defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: dismissedIdsKey) ?? []
    }

    public static func saveDismissedIds(_ ids: [String], to defaults: UserDefaults = .standard) {
        defaults.set(ids, forKey: dismissedIdsKey)
    }

    public static func isDismissed(_ id: String, dismissedIds: [String]) -> Bool {
        dismissedIds.contains(id)
    }

    public static func dismissedIds(afterDismissing id: String, currentIds: [String]) -> [String] {
        var ids = currentIds
        if !ids.contains(id) {
            ids.append(id)
        }

        if ids.count > maxDismissedIdsToKeep {
            ids.removeFirst(ids.count - maxDismissedIdsToKeep)
        }

        return ids
    }
}

public enum VoiceInkAnnouncementPolicy {
    public static func nextAnnouncement(
        from announcements: [VoiceInkRemoteAnnouncement],
        dismissedIds: [String],
        now: Date
    ) -> VoiceInkAnnouncementPresentation? {
        let formatter = ISO8601DateFormatter()

        guard let announcement = announcements.first(where: {
            !VoiceInkAnnouncementPreference.isDismissed($0.id, dismissedIds: dismissedIds)
                && isActive($0, at: now, formatter: formatter)
        }) else {
            return nil
        }

        return VoiceInkAnnouncementPresentation(
            id: announcement.id,
            title: announcement.title,
            description: announcement.description,
            learnMoreURL: announcement.url.flatMap(URL.init(string:))
        )
    }

    public static func isActive(
        _ announcement: VoiceInkRemoteAnnouncement,
        at date: Date
    ) -> Bool {
        isActive(announcement, at: date, formatter: ISO8601DateFormatter())
    }

    private static func isActive(
        _ announcement: VoiceInkRemoteAnnouncement,
        at date: Date,
        formatter: ISO8601DateFormatter
    ) -> Bool {
        if let startAt = announcement.startAt,
           let start = formatter.date(from: startAt),
           date < start {
            return false
        }

        if let endAt = announcement.endAt,
           let end = formatter.date(from: endAt),
           date > end {
            return false
        }

        return true
    }
}
