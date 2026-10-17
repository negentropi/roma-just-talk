import Foundation
import RomaCore

final class RecordingStartupAudioRelay: @unchecked Sendable {
    private let queue = DispatchQueue(label: "\(RomaAppIdentity.loggingSubsystem).recordingStartupAudioRelay")
    private let latencyTraceToken: RomaLatencyTrace.Token?
    private var bufferedChunks: [Data] = []
    private var sink: ((Data) -> Void)?

    init(latencyTraceToken: RomaLatencyTrace.Token? = nil) {
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
        let span = RomaLatencyTrace.shared.begin(
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
        RomaLatencyTrace.shared.end(
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
        RomaLatencyTrace.shared.event(
            "audio_relay.cleared",
            details: "chunks=\(clearedChunkCount)",
            token: latencyTraceToken
        )
    }
}
