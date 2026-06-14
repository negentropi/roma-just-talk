import Foundation

protocol SpeechActivityDetecting: Sendable {
    func containsSpeech(inPCM16LEData data: Data) -> Bool
}

final class AudioChunkSpeechGate: @unchecked Sendable {
    private let detector: any SpeechActivityDetecting
    private let leadInChunkCount: Int
    private var leadInBuffer: [Data] = []
    private var hasDetectedSpeech = false

    init(
        detector: any SpeechActivityDetecting,
        leadInChunkCount: Int = 120
    ) {
        self.detector = detector
        self.leadInChunkCount = max(0, leadInChunkCount)
    }

    func accept(_ chunk: Data) -> [Data] {
        guard !chunk.isEmpty else { return [] }
        // After speech starts, reliability beats silence trimming: a VAD false negative
        // must not remove words from the live transcript payload.
        guard !hasDetectedSpeech else { return [chunk] }

        if detector.containsSpeech(inPCM16LEData: chunk) {
            let buffered = leadInBuffer
            leadInBuffer.removeAll(keepingCapacity: true)
            hasDetectedSpeech = true
            return buffered + [chunk]
        }

        guard leadInChunkCount > 0 else { return [] }

        leadInBuffer.append(chunk)
        if leadInBuffer.count > leadInChunkCount {
            leadInBuffer.removeFirst(leadInBuffer.count - leadInChunkCount)
        }
        return []
    }
}
