//
//  TranscriptionServiceFactory.swift
//

import Foundation
import VoiceInkCore

struct TranscriptionServiceFactory {
    static func service(for provider: VoiceInkProviderKind) -> TranscriptionService {
        switch provider.transcriptionTransport {
        case .deepgram, .openAICompatible:
            return RemoteTranscriptionService(
                transport: provider.transcriptionTransport
            )
        case .localWhisper:
            return WhisperTranscriptionService()
        }
    }
}
