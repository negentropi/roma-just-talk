import Foundation
import VoiceInkCore

enum VoiceInkAppDeepLink: Equatable {
    private static let scheme = VoiceInkAppIdentity.iOSRecordDeepLinkScheme
    private static let recordHost = VoiceInkAppIdentity.iOSRecordDeepLinkHost

    case record

    var url: URL {
        switch self {
        case .record:
            return VoiceInkAppIdentity.iOSRecordDeepLinkURL
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
