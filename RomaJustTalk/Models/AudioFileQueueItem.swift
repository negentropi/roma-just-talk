import Foundation
import RomaCore

@MainActor
class AudioFileQueueItem: Identifiable, ObservableObject {
    let id = UUID()
    let url: URL
    let filename: String

    @Published var status: RomaAudioFileQueueStatus = .pending
    @Published var transcription: Transcription?

    init(url: URL) {
        self.url = url
        self.filename = url.lastPathComponent
    }
}
