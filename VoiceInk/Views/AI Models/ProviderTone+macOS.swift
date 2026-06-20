import SwiftUI
import VoiceInkCore

extension VoiceInkProviderAPIKeyVerificationTone {
    var macOSStatusColor: Color {
        switch self {
        case .success:
            return Color(.systemGreen)
        case .failure:
            return Color(.systemRed)
        }
    }
}

extension VoiceInkAIEnhancementConnectionStatusTone {
    var macOSStatusColor: Color {
        switch self {
        case .connected:
            return .green
        case .disconnected:
            return .red
        }
    }
}
