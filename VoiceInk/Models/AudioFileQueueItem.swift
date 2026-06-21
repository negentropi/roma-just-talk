import Foundation
import VoiceInkCore

@MainActor
class AudioFileQueueItem: Identifiable, ObservableObject {
    let id = UUID()
    let url: URL
    let filename: String

    @Published var status: VoiceInkAudioFileQueueStatus = .pending
    @Published var transcription: Transcription?

    init(url: URL) {
        self.url = url
        self.filename = url.lastPathComponent
    }
}
