import Foundation
import os
import VoiceInkCore

class VADModelManager {
    static let shared = VADModelManager()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "VADModelManager")
    private var modelPath: String?

    private init() {
        if let path = VoiceInkVADModelFiles.sileroPath() {
            self.modelPath = path
            logger.info("VAD model found at path: \(path)")
        } else {
            logger.error("VAD model '\(VoiceInkVADModelFiles.sileroFilename)' not found in bundle resources.")
        }
    }

    func getModelPath() -> String? {
        return modelPath
    }
}
