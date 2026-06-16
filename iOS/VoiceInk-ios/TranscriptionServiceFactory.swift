//
//  TranscriptionServiceFactory.swift
//

import Foundation
import VoiceInkCore

struct TranscriptionServiceFactory {
    static func service(for provider: VoiceInkProviderKind) -> any VoiceInkAudioTranscriptionService {
        switch provider.transcriptionTransport {
        case .deepgram, .openAICompatible:
            return VoiceInkRemoteTranscriptionService(
                provider: provider
            )
        case .localWhisper:
            return WhisperTranscriptionService()
        }
    }
}
