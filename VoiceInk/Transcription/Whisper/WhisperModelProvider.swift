import Foundation
import SwiftData
import VoiceInkCore

/// Protocol that WhisperModelManager conforms to, decoupling TranscriptionServiceRegistry
/// and WhisperTranscriptionService from concrete manager types.
@MainActor
protocol WhisperModelProvider: AnyObject {
    var isModelLoaded: Bool { get }
    var whisperContext: WhisperContext? { get }
    var loadedWhisperModel: VoiceInkWhisperLocalModelFile? { get }
    var availableModels: [VoiceInkWhisperLocalModelFile] { get }
}
