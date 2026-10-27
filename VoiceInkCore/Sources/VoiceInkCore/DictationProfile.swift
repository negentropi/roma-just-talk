import Foundation

public enum VoiceInkDictationProfile: String, Codable, CaseIterable, Sendable {
    case custom
    case none

    public static let storageKey = "VoiceInkDictationProfile"

    public static func current(in defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? .custom
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.storageKey)
    }
}
