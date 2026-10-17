import SwiftUI
import RomaCore

extension RomaWhisperModelDownloadRowActionTint {
    var iOSColor: Color {
        switch self {
        case .primary:
            return .blue
        case .destructive:
            return .red
        case .success:
            return .green
        }
    }

    var onboardingColor: Color {
        switch self {
        case .primary, .destructive:
            return .accentColor
        case .success:
            return .green
        }
    }
}
