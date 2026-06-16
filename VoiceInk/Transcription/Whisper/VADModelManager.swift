import Foundation
import OSLog
import VoiceInkCore

class VADModelManager {
    static let shared = VADModelManager()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ModelManagement")
    
    private init() {}

    func getModelPath() async -> String? {
        guard let path = VoiceInkVADModelFiles.sileroPath() else {
            logger.error("VAD model not found in bundle resources")
            return nil
        }
        
        return path
    }
} 
