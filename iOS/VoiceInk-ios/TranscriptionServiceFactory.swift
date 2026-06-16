//
//  TranscriptionServiceFactory.swift
//

import Foundation
import VoiceInkCore

struct TranscriptionServiceFactory {
    static func service(for provider: Provider) -> TranscriptionService {
        switch provider.coreKind.transcriptionTransport {
        case .deepgram:
            return DeepgramTranscriptionService()
        case .openAICompatible:
            return GroqTranscriptionService()
        case .localWhisper:
            return WhisperTranscriptionService()
        }
    }
}
