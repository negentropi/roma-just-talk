import Foundation

enum VoiceInkAppDeepLink: Equatable {
    private static let scheme = "voiceink"
    private static let recordHost = "record"

    case record

    var url: URL {
        switch self {
        case .record:
            return URL(string: "\(Self.scheme)://\(Self.recordHost)")!
        }
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme else {
            return nil
        }

        guard url.host == Self.recordHost else {
            return nil
        }

        self = .record
    }
}
