import Foundation
import AVFoundation
import SwiftUI
import VoiceInkCore

extension VoiceInkBuiltInRecordingSound {
    var bundleURL: URL? {
        Bundle.main.url(forResource: rawValue, withExtension: fileExtension) ??
            Bundle.main.url(forResource: rawValue, withExtension: fileExtension, subdirectory: "Sounds")
    }
}

class CustomSoundManager: ObservableObject {
    static let shared = CustomSoundManager()

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

    @Published private(set) var selectedStartBuiltInSound: VoiceInkBuiltInRecordingSound {
        didSet {
            VoiceInkCustomSoundPreference.saveSelectedBuiltInSound(selectedStartBuiltInSound, for: .start)
        }
    }

    @Published private(set) var selectedStopBuiltInSound: VoiceInkBuiltInRecordingSound {
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
    
    private func updateFilenameInUserDefaults(filename: String?, for type: VoiceInkCustomSoundType) {
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

    func getCustomSoundURL(for type: VoiceInkCustomSoundType) -> URL? {
        let isUsing = (type == .start) ? isUsingCustomStartSound : isUsingCustomStopSound
        let filename = (type == .start) ? customStartSoundFilename : customStopSoundFilename

        return VoiceInkCustomSoundPreference.customSoundURL(
            isUsingCustomSound: isUsing,
            filename: filename,
            in: customSoundsDirectory()
        )
    }

    func builtInSoundURL(for type: VoiceInkCustomSoundType) -> URL? {
        selectedBuiltInSound(for: type).bundleURL
    }

    func selectedBuiltInSound(for type: VoiceInkCustomSoundType) -> VoiceInkBuiltInRecordingSound {
        switch type {
        case .start:
            return selectedStartBuiltInSound
        case .stop:
            return selectedStopBuiltInSound
        }
    }

    func selectBuiltInSound(_ sound: VoiceInkBuiltInRecordingSound, for type: VoiceInkCustomSoundType) {
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

    func useCustomSound(for type: VoiceInkCustomSoundType) {
        guard getSoundDisplayName(for: type) != nil else { return }

        switch type {
        case .start:
            isUsingCustomStartSound = true
        case .stop:
            isUsingCustomStopSound = true
        }

        notifyCustomSoundsChanged()
    }

    func setCustomSound(url: URL, for type: VoiceInkCustomSoundType) -> Result<Void, VoiceInkCustomSoundError> {
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

    func resetSoundToDefault(for type: VoiceInkCustomSoundType) {
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

    func getSoundDisplayName(for type: VoiceInkCustomSoundType) -> String? {
        return (type == .start) ? customStartSoundFilename : customStopSoundFilename
    }

    func isDefaultSelection(for type: VoiceInkCustomSoundType) -> Bool {
        let isUsingCustom = (type == .start) ? isUsingCustomStartSound : isUsingCustomStopSound
        return VoiceInkCustomSoundPreference.isDefaultSelection(
            for: type,
            isUsingCustomSound: isUsingCustom,
            selectedBuiltInSound: selectedBuiltInSound(for: type)
        )
    }

    private func copySoundFile(from sourceURL: URL, for type: VoiceInkCustomSoundType) -> Result<String, VoiceInkCustomSoundError> {
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

    private func validateAudioFile(url: URL) -> Result<Void, VoiceInkCustomSoundError> {
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
