import Foundation
import VoiceInkCore

// Protocol for objects that provide live recorder state to the UI.
@MainActor
protocol RecorderStateProvider: AnyObject {
    var recordingState: VoiceInkRecordingState { get }
    var partialTranscript: String { get }
    var enhancementService: AIEnhancementService? { get }
}
