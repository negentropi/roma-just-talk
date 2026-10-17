import Foundation
import SwiftData
import RomaCore

/// Protocol that WhisperModelManager conforms to, decoupling TranscriptionServiceRegistry
/// and WhisperTranscriptionService from concrete manager types.
@MainActor
protocol WhisperModelProvider: AnyObject {
    var isModelLoaded: Bool { get }
    var whisperContext: WhisperContext? { get }
    var loadedWhisperModel: RomaWhisperLocalModelFile? { get }
    var availableModels: [RomaWhisperLocalModelFile] { get }
}
