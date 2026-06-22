import Foundation
import AVFoundation
import SwiftUI
import VoiceInkCore

typealias CustomSoundError = VoiceInkCustomSoundError

extension VoiceInkBuiltInRecordingSound {
    var bundleURL: URL? {
        Bundle.main.url(forResource: rawValue, withExtension: fileExtension) ??
            Bundle.main.url(forResource: rawValue, withExtension: fileExtension, subdirectory: "Sounds")
    }
}

class CustomSoundManager: ObservableObject {
    static let shared = CustomSoundManager()

    typealias BuiltInSound = VoiceInkBuiltInRecordingSound
    typealias SoundType = VoiceInkCustomSoundType

    @Published var isUsingCustomStartSound: Bool {
        didSet {
            VoiceInkCustomSoundPreference.saveIsUsingCustomSound(isUsingCustomStartSound, for: .start)
        }
    }

    @Published var isUsingCustomStopSound: Bool {
        didSet {
            VoiceInkCustomSoundPreference.saveIsUsingCustomSound(isUsingCustomStopSound, for: .stop)
        }
    }

    @Published private(set) var selectedStartBuiltInSound: BuiltInSound {
        didSet {
            VoiceInkCustomSoundPreference.saveSelectedBuiltInSound(selectedStartBuiltInSound, for: .start)
        }
    }

    @Published private(set) var selectedStopBuiltInSound: BuiltInSound {
        didSet {
            VoiceInkCustomSoundPreference.saveSelectedBuiltInSound(selectedStopBuiltInSound, for: .stop)
        }
    }

    private var customStartSoundFilename: String? {
        didSet { updateFilenameInUserDefaults(filename: customStartSoundFilename, for: .start) }
    }

    private var customStopSoundFilename: String? {
        didSet { updateFilenameInUserDefaults(filename: customStopSoundFilename, for: .stop) }
    }
    
    private func updateFilenameInUserDefaults(filename: String?, for type: SoundType) {
        VoiceInkCustomSoundPreference.saveCustomFilename(filename, for: type)
    }

    private init() {
        self.isUsingCustomStartSound = VoiceInkCustomSoundPreference.isUsingCustomSound(for: .start)
        self.isUsingCustomStopSound = VoiceInkCustomSoundPreference.isUsingCustomSound(for: .stop)
        self.selectedStartBuiltInSound = VoiceInkCustomSoundPreference.selectedBuiltInSound(for: .start)
        self.selectedStopBuiltInSound = VoiceInkCustomSoundPreference.selectedBuiltInSound(for: .stop)
        self.customStartSoundFilename = VoiceInkCustomSoundPreference.customFilename(for: .start)
        self.customStopSoundFilename = VoiceInkCustomSoundPreference.customFilename(for: .stop)

        createCustomSoundsDirectoryIfNeeded()
    }

    private func customSoundsDirectory() -> URL? {
        VoiceInkMacOSStorageDirectories.customSoundsDirectory
    }

    private func createCustomSoundsDirectoryIfNeeded() {
        guard let directory = customSoundsDirectory() else { return }

        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func getCustomSoundURL(for type: SoundType) -> URL? {
        let isUsing = (type == .start) ? isUsingCustomStartSound : isUsingCustomStopSound
        let filename = (type == .start) ? customStartSoundFilename : customStopSoundFilename

        return VoiceInkCustomSoundPreference.customSoundURL(
            isUsingCustomSound: isUsing,
            filename: filename,
            in: customSoundsDirectory()
        )
    }

    func builtInSoundURL(for type: SoundType) -> URL? {
        selectedBuiltInSound(for: type).bundleURL
    }

    func selectedBuiltInSound(for type: SoundType) -> BuiltInSound {
        switch type {
        case .start:
            return selectedStartBuiltInSound
        case .stop:
            return selectedStopBuiltInSound
        }
    }

    func selectBuiltInSound(_ sound: BuiltInSound, for type: SoundType) {
        switch type {
        case .start:
            selectedStartBuiltInSound = sound
            isUsingCustomStartSound = false
        case .stop:
            selectedStopBuiltInSound = sound
            isUsingCustomStopSound = false
        }

        notifyCustomSoundsChanged()
    }

    func useCustomSound(for type: SoundType) {
        guard getSoundDisplayName(for: type) != nil else { return }

        switch type {
        case .start:
            isUsingCustomStartSound = true
        case .stop:
            isUsingCustomStopSound = true
        }

        notifyCustomSoundsChanged()
    }

    func setCustomSound(url: URL, for type: SoundType) -> Result<Void, CustomSoundError> {
        let result = validateAudioFile(url: url)
        switch result {
        case .success:
            let copyResult = copySoundFile(from: url, for: type)
            switch copyResult {
            case .success(let filename):
                if type == .start {
                    customStartSoundFilename = filename
                    isUsingCustomStartSound = true
                } else {
                    customStopSoundFilename = filename
                    isUsingCustomStopSound = true
                }
                notifyCustomSoundsChanged()
                return .success(())
            case .failure(let error):
                return .failure(error)
            }
        case .failure(let error):
            return .failure(error)
        }
    }

    func resetSoundToDefault(for type: SoundType) {
        let filename = (type == .start) ? customStartSoundFilename : customStopSoundFilename

        if let fileURL = VoiceInkCustomSoundPreference.storedCustomSoundURL(
            filename: filename,
            in: customSoundsDirectory()
        ) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        if type == .start {
            selectedStartBuiltInSound = type.defaultBuiltInSound
            isUsingCustomStartSound = false
            customStartSoundFilename = nil
        } else {
            selectedStopBuiltInSound = type.defaultBuiltInSound
            isUsingCustomStopSound = false
            customStopSoundFilename = nil
        }
        notifyCustomSoundsChanged()
    }

    private func notifyCustomSoundsChanged() {
        NotificationCenter.default.post(
            name: NSNotification.Name(VoiceInkCustomSoundPreference.changedNotificationName),
            object: nil
        )
    }

    func getSoundDisplayName(for type: SoundType) -> String? {
        return (type == .start) ? customStartSoundFilename : customStopSoundFilename
    }

    func isDefaultSelection(for type: SoundType) -> Bool {
        let isUsingCustom = (type == .start) ? isUsingCustomStartSound : isUsingCustomStopSound
        return VoiceInkCustomSoundPreference.isDefaultSelection(
            for: type,
            isUsingCustomSound: isUsingCustom,
            selectedBuiltInSound: selectedBuiltInSound(for: type)
        )
    }

    private func copySoundFile(from sourceURL: URL, for type: SoundType) -> Result<String, CustomSoundError> {
        guard let directory = customSoundsDirectory() else {
            return .failure(.directoryCreationFailed)
        }

        let copyPlan = VoiceInkCustomSoundPreference.copyPlan(
            sourceURL: sourceURL,
            customSoundsDirectory: directory,
            for: type
        )

        switch copyPlan.action {
        case .useExistingDestination:
            return .success(copyPlan.filename)
        case .replaceExistingDestinationAndCopy:
            try? FileManager.default.removeItem(at: copyPlan.destinationURL)
        case .copy:
            break
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: copyPlan.destinationURL)
            return .success(copyPlan.filename)
        } catch {
            return .failure(.fileCopyFailed)
        }
    }

    private func validateAudioFile(url: URL) -> Result<Void, CustomSoundError> {
        let fileExists = FileManager.default.fileExists(atPath: url.path)
        guard fileExists else {
            return .failure(
                VoiceInkCustomSoundPreference.preflightValidationError(fileExists: false, duration: 0) ?? .fileNotFound
            )
        }

        let asset = AVAsset(url: url)
        let duration = asset.duration.seconds

        if let error = VoiceInkCustomSoundPreference.preflightValidationError(
            fileExists: true,
            duration: duration
        ) {
            return .failure(error)
        }

        do {
            _ = try AVAudioPlayer(contentsOf: url)
        } catch {
            return .failure(.invalidAudioFile)
        }

        return .success(())
    }
}
