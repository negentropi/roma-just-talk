import Foundation
import VoiceInkCore

struct VoiceInkKeyboardRecordingButtonPresentation: Equatable {
    let title: String
    let systemImageName: String

    static let idle = VoiceInkKeyboardRecordingButtonPresentation(
        title: " Record",
        systemImageName: "mic.fill"
    )

    static let recording = VoiceInkKeyboardRecordingButtonPresentation(
        title: " Stop",
        systemImageName: "stop.fill"
    )

    static let openAppFallback = VoiceInkKeyboardRecordingButtonPresentation(
        title: " Open \(VoiceInkAppIdentity.displayName)",
        systemImageName: "app"
    )

    static func current(isRecording: Bool) -> VoiceInkKeyboardRecordingButtonPresentation {
        isRecording ? recording : idle
    }
}
