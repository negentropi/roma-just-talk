import Foundation
import VoiceInkCore

final class RecordingStartupAudioRelay: @unchecked Sendable {
    private let queue = DispatchQueue(label: "\(VoiceInkAppIdentity.loggingSubsystem).recordingStartupAudioRelay")
    private let latencyTraceToken: VoiceInkLatencyTrace.Token?
    private var bufferedChunks: [Data] = []
    private var sink: ((Data) -> Void)?

    init(latencyTraceToken: VoiceInkLatencyTrace.Token? = nil) {
        self.latencyTraceToken = latencyTraceToken
    }

    func handle(_ data: Data) {
        queue.async { [data] in
            if let sink = self.sink {
                sink(data)
            } else {
                self.bufferedChunks.append(data)
            }
        }
    }

    func installSink(_ sink: @escaping (Data) -> Void) {
        let span = VoiceInkLatencyTrace.shared.begin(
            "audio_relay.flush_buffered_chunks",
            token: latencyTraceToken
        )
        var flushedChunkCount = 0
        queue.sync {
            flushedChunkCount = bufferedChunks.count
            for chunk in bufferedChunks {
                sink(chunk)
            }
            bufferedChunks.removeAll(keepingCapacity: true)
            self.sink = sink
        }
        VoiceInkLatencyTrace.shared.end(
            span,
            details: "chunks=\(flushedChunkCount)"
        )
    }

    func clear() {
        var clearedChunkCount = 0
        queue.sync {
            clearedChunkCount = bufferedChunks.count
            bufferedChunks.removeAll(keepingCapacity: true)
            sink = nil
        }
        VoiceInkLatencyTrace.shared.event(
            "audio_relay.cleared",
            details: "chunks=\(clearedChunkCount)",
            token: latencyTraceToken
        )
    }
}
