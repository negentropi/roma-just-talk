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
        let startState = VoiceInkCustomSoundPreference.selectionState(for: .start)
        let stopState = VoiceInkCustomSoundPreference.selectionState(for: .stop)
        self.isUsingCustomStartSound = startState.isUsingCustomSound
        self.isUsingCustomStopSound = stopState.isUsingCustomSound
        self.selectedStartBuiltInSound = startState.selectedBuiltInSound
        self.selectedStopBuiltInSound = stopState.selectedBuiltInSound
        self.customStartSoundFilename = startState.customFilename
        self.customStopSoundFilename = stopState.customFilename

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
        customSoundSelectionState(for: type).customSoundURL(in: customSoundsDirectory())
    }

    func builtInSoundURL(for type: VoiceInkCustomSoundType) -> URL? {
        selectedBuiltInSound(for: type).bundleURL
    }

    func selectedBuiltInSound(for type: VoiceInkCustomSoundType) -> VoiceInkBuiltInRecordingSound {
        customSoundSelectionState(for: type).selectedBuiltInSound
    }

    func isUsingCustomSound(for type: VoiceInkCustomSoundType) -> Bool {
        customSoundSelectionState(for: type).isUsingCustomSound
    }

    func menuSelection(for type: VoiceInkCustomSoundType) -> VoiceInkCustomSoundMenuSelection {
        customSoundSelectionState(for: type).menuSelection
    }

    func selectBuiltInSound(_ sound: VoiceInkBuiltInRecordingSound, for type: VoiceInkCustomSoundType) {
        applyCustomSoundSelectionState(
            customSoundSelectionState(for: type).selectingBuiltInSound(sound)
        )
        notifyCustomSoundsChanged()
    }

    func useCustomSound(for type: VoiceInkCustomSoundType) {
        guard let state = customSoundSelectionState(for: type).usingExistingCustomSound() else { return }
        applyCustomSoundSelectionState(state)
        notifyCustomSoundsChanged()
    }

    func setCustomSound(url: URL, for type: VoiceInkCustomSoundType) -> Result<Void, VoiceInkCustomSoundError> {
        let result = validateAudioFile(url: url)
        switch result {
        case .success:
            let copyResult = copySoundFile(from: url, for: type)
            switch copyResult {
            case .success(let filename):
                applyCustomSoundSelectionState(
                    customSoundSelectionState(for: type).settingCustomFilename(filename)
                )
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
        let currentState = customSoundSelectionState(for: type)

        if let fileURL = currentState.storedCustomSoundURL(in: customSoundsDirectory()) {
            try? FileManager.default.removeItem(at: fileURL)
        }

        applyCustomSoundSelectionState(currentState.resettingToDefault())
        notifyCustomSoundsChanged()
    }

    private func notifyCustomSoundsChanged() {
        NotificationCenter.default.post(
            name: NSNotification.Name(VoiceInkCustomSoundPreference.changedNotificationName),
            object: nil
        )
    }

    func getSoundDisplayName(for type: VoiceInkCustomSoundType) -> String? {
        customSoundSelectionState(for: type).customFilename
    }

    func isDefaultSelection(for type: VoiceInkCustomSoundType) -> Bool {
        customSoundSelectionState(for: type).isDefaultSelection
    }

    private func customSoundSelectionState(
        for type: VoiceInkCustomSoundType
    ) -> VoiceInkCustomSoundSelectionState {
        switch type {
        case .start:
            return VoiceInkCustomSoundSelectionState(
                type: type,
                isUsingCustomSound: isUsingCustomStartSound,
                selectedBuiltInSound: selectedStartBuiltInSound,
                customFilename: customStartSoundFilename
            )
        case .stop:
            return VoiceInkCustomSoundSelectionState(
                type: type,
                isUsingCustomSound: isUsingCustomStopSound,
                selectedBuiltInSound: selectedStopBuiltInSound,
                customFilename: customStopSoundFilename
            )
        }
    }

    private func applyCustomSoundSelectionState(_ state: VoiceInkCustomSoundSelectionState) {
        switch state.type {
        case .start:
            selectedStartBuiltInSound = state.selectedBuiltInSound
            customStartSoundFilename = state.customFilename
            isUsingCustomStartSound = state.isUsingCustomSound
        case .stop:
            selectedStopBuiltInSound = state.selectedBuiltInSound
            customStopSoundFilename = state.customFilename
            isUsingCustomStopSound = state.isUsingCustomSound
        }
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

        return copyPlan.applyRuntimeState(
            removeExistingDestination: { try FileManager.default.removeItem(at: $0) },
            copyToDestination: { try FileManager.default.copyItem(at: sourceURL, to: $0) }
        )
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
