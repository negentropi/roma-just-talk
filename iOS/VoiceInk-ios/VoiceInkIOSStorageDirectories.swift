import Foundation
import VoiceInkCore

enum VoiceInkIOSStorageDirectories {
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var recordingsDirectory: URL {
        VoiceInkStoredAudioFile.recordingsDirectory(in: documentsDirectory)
    }

    static var preparedRecordingsDirectory: URL {
        (try? VoiceInkStoredAudioFile.createRecordingsDirectory(in: documentsDirectory))
            ?? recordingsDirectory
    }

    static var modelsDirectory: URL {
        VoiceInkWhisperModelFiles.modelsDirectory(in: documentsDirectory)
    }

    static var preparedModelsDirectory: URL {
        (try? VoiceInkWhisperModelFiles.createModelsDirectory(in: documentsDirectory))
            ?? modelsDirectory
    }

    static var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }
}
