import Foundation
import RomaCore

// Protocol for objects that provide live recorder state to the UI.
@MainActor
protocol RecorderStateProvider: AnyObject {
    var recordingState: RomaRecordingState { get }
    var partialTranscript: String { get }
    var enhancementService: AIEnhancementService? { get }
}
