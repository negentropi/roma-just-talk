import SwiftUI
import RomaCore

extension RomaProviderAPIKeyVerificationTone {
    var macOSStatusColor: Color {
        switch self {
        case .success:
            return Color(.systemGreen)
        case .failure:
            return Color(.systemRed)
        }
    }
}

extension RomaAIEnhancementConnectionStatusTone {
    var macOSStatusColor: Color {
        switch self {
        case .connected:
            return .green
        case .disconnected:
            return .red
        }
    }
}
