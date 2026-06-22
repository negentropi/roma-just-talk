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

public enum VoiceInkMacOSStorageDirectories {
    public static var applicationSupportBaseDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    public static func appSupportDirectory(in applicationSupportBaseDirectory: URL) -> URL {
        VoiceInkAppIdentity.macOSApplicationSupportDirectory(in: applicationSupportBaseDirectory)
    }

    public static var appSupportDirectory: URL {
        appSupportDirectory(in: applicationSupportBaseDirectory)
    }

    public static func recordingsDirectory(in appSupportDirectory: URL) -> URL {
        VoiceInkStoredAudioFile.recordingsDirectory(in: appSupportDirectory)
    }

    public static var recordingsDirectory: URL {
        recordingsDirectory(in: appSupportDirectory)
    }

    public static func modelsDirectory(in appSupportDirectory: URL) -> URL {
        VoiceInkWhisperModelFiles.modelsDirectory(in: appSupportDirectory)
    }

    public static var modelsDirectory: URL {
        modelsDirectory(in: appSupportDirectory)
    }

    public static func customSoundsDirectory(in applicationSupportBaseDirectory: URL) -> URL {
        applicationSupportBaseDirectory.appendingPathComponent(
            VoiceInkCustomSoundPreference.customSoundsRelativeDirectory,
            isDirectory: true
        )
    }

    public static var customSoundsDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            .map { customSoundsDirectory(in: $0) }
    }
}
