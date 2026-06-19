import Foundation
import VoiceInkCore

final class RecordingStartupAudioRelay: @unchecked Sendable {
    private let queue = DispatchQueue(label: "\(VoiceInkAppIdentity.loggingSubsystem).recordingStartupAudioRelay")
    private var bufferedChunks: [Data] = []
    private var sink: ((Data) -> Void)?

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
        queue.sync {
            for chunk in bufferedChunks {
                sink(chunk)
            }
            bufferedChunks.removeAll(keepingCapacity: true)
            self.sink = sink
        }
    }

    func clear() {
        queue.sync {
            bufferedChunks.removeAll(keepingCapacity: true)
            sink = nil
        }
    }
}
