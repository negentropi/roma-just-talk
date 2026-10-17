import SwiftUI
import RomaCore

extension RomaProviderAPIKeyListRowTone {
    var statusColor: Color {
        switch self {
        case .verified:
            return .green
        case .attention:
            return .orange
        }
    }
}

extension RomaProviderAPIKeyVerificationTone {
    var statusColor: Color {
        switch self {
        case .success:
            return .green
        case .failure:
            return .red
        }
    }
}
