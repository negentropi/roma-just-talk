import Foundation

public enum VoiceInkIOSStorageDirectories {
    public static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    public static func recordingsDirectory(in documentsDirectory: URL) -> URL {
        VoiceInkStoredAudioFile.recordingsDirectory(in: documentsDirectory)
    }

    public static var recordingsDirectory: URL {
        recordingsDirectory(in: documentsDirectory)
    }

    public static func preparedRecordingsDirectory(
        in documentsDirectory: URL,
        fileManager: FileManager = .default
    ) -> URL {
        (try? VoiceInkStoredAudioFile.createRecordingsDirectory(
            in: documentsDirectory,
            fileManager: fileManager
        )) ?? recordingsDirectory(in: documentsDirectory)
    }

    public static var preparedRecordingsDirectory: URL {
        preparedRecordingsDirectory(in: documentsDirectory)
    }

    public static func modelsDirectory(in documentsDirectory: URL) -> URL {
        VoiceInkWhisperModelFiles.modelsDirectory(in: documentsDirectory)
    }

    public static var modelsDirectory: URL {
        modelsDirectory(in: documentsDirectory)
    }

    public static func preparedModelsDirectory(
        in documentsDirectory: URL,
        fileManager: FileManager = .default
    ) -> URL {
        (try? VoiceInkWhisperModelFiles.createModelsDirectory(
            in: documentsDirectory,
            fileManager: fileManager
        )) ?? modelsDirectory(in: documentsDirectory)
    }

    public static var preparedModelsDirectory: URL {
        preparedModelsDirectory(in: documentsDirectory)
    }

    public static var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }
}
