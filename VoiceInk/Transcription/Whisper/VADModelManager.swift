import Foundation
import OSLog
import VoiceInkCore

class VADModelManager {
    static let shared = VADModelManager()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ModelManagement")
    
    private init() {}

    func getModelPath() async -> String? {
        guard let modelURL = Bundle.main.url(
            forResource: VoiceInkVADModelFiles.sileroResourceName,
            withExtension: VoiceInkVADModelFiles.sileroFileExtension
        ) else {
            logger.error("VAD model not found in bundle resources")
            return nil
        }
        
        return modelURL.path
    }
} 
