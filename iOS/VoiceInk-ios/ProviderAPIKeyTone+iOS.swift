import SwiftUI
import VoiceInkCore

extension VoiceInkProviderAPIKeyListRowTone {
    var statusColor: Color {
        switch self {
        case .verified:
            return .green
        case .attention:
            return .orange
        }
    }
}

extension VoiceInkProviderAPIKeyVerificationTone {
    var statusColor: Color {
        switch self {
        case .success:
            return .green
        case .failure:
            return .red
        }
    }
}
