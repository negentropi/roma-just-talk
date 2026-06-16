//
//  TranscriptionServiceFactory.swift
//

import Foundation
import VoiceInkCore

struct TranscriptionServiceFactory {
    static func service(for provider: Provider) -> TranscriptionService {
        switch provider.coreKind.transcriptionTransport {
        case .deepgram, .openAICompatible:
            return RemoteTranscriptionService(
                transport: provider.coreKind.transcriptionTransport
            )
        case .localWhisper:
            return WhisperTranscriptionService()
        }
    }
}
