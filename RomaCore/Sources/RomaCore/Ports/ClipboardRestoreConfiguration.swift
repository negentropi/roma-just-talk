import Foundation

public struct ClipboardRestoreConfiguration: Codable, Equatable, Hashable, Sendable {
    public static let defaultRestoreClipboard = true
    public static let defaultRestoreDelaySeconds: TimeInterval = 2
    public static let maximumRestoreDelaySeconds = Double(UInt32.max) / 1_000

    public var restoreClipboard: Bool
    public var restoreDelaySeconds: TimeInterval

    public init(
        restoreClipboard: Bool = Self.defaultRestoreClipboard,
        restoreDelaySeconds: TimeInterval = Self.defaultRestoreDelaySeconds
    ) {
        self.restoreClipboard = restoreClipboard
        self.restoreDelaySeconds = restoreDelaySeconds
    }

    public static func restoreDelayMilliseconds(fromSeconds seconds: TimeInterval) -> UInt32? {
        guard seconds.isFinite,
              seconds >= 0,
              seconds <= maximumRestoreDelaySeconds else {
            return nil
        }
        return UInt32(seconds * 1_000)
    }
}
