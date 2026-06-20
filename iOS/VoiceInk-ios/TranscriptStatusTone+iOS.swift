import SwiftUI
import VoiceInkCore

extension VoiceInkTranscriptStatusPresentation.Tone {
    var statusColor: Color {
        switch self {
        case .processing:
            return .orange
        case .failure:
            return .red
        }
    }

    var badgeColor: Color {
        switch self {
        case .processing:
            return .secondary
        case .failure:
            return .orange
        }
    }

    var badgeBackgroundColor: Color {
        badgeColor.opacity(0.12)
    }
}
