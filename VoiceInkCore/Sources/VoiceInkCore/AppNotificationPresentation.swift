import Foundation

public enum VoiceInkAppNotificationKind: String, CaseIterable, Sendable {
    case error
    case warning
    case info
    case success

    public static let defaultDisplayDuration: TimeInterval = 3.0

    public var systemImageName: String {
        switch self {
        case .error:
            return "xmark.octagon.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        }
    }

    public var playsFailureSound: Bool {
        self == .error
    }
}
