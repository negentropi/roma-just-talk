import Foundation
import VoiceInkCore

enum VoiceInkMacOSStorageDirectories {
    static var applicationSupportBaseDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var appSupportDirectory: URL {
        VoiceInkAppIdentity.macOSApplicationSupportDirectory(in: applicationSupportBaseDirectory)
    }

    static var recordingsDirectory: URL {
        VoiceInkStoredAudioFile.recordingsDirectory(in: appSupportDirectory)
    }

    static var modelsDirectory: URL {
        VoiceInkWhisperModelFiles.modelsDirectory(in: appSupportDirectory)
    }

    static var customSoundsDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(VoiceInkCustomSoundPreference.customSoundsRelativeDirectory, isDirectory: true)
    }
}
