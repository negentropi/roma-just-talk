import Foundation
import AVFoundation
import SwiftUI
import RomaCore

extension RomaBuiltInRecordingSound {
    var bundleURL: URL? {
        Bundle.main.url(forResource: rawValue, withExtension: fileExtension) ??
            Bundle.main.url(forResource: rawValue, withExtension: fileExtension, subdirectory: "Sounds")
    }
}

class CustomSoundManager: ObservableObject {
    static let shared = CustomSoundManager()

    @Published var isUsingCustomStartSound: Bool {
        didSet {
            RomaCustomSoundPreference.saveIsUsingCustomSound(isUsingCustomStartSound, for: .start)
        }
    }

    @Published var isUsingCustomStopSound: Bool {
        didSet {
            RomaCustomSoundPreference.saveIsUsingCustomSound(isUsingCustomStopSound, for: .stop)
        }
    }

    @Published private(set) var selectedStartBuiltInSound: RomaBuiltInRecordingSound {
        didSet {
            RomaCustomSoundPreference.saveSelectedBuiltInSound(selectedStartBuiltInSound, for: .start)
        }
    }

    @Published private(set) var selectedStopBuiltInSound: RomaBuiltInRecordingSound {
        didSet {
            RomaCustomSoundPreference.saveSelectedBuiltInSound(selectedStopBuiltInSound, for: .stop)
        }
    }

    private var customStartSoundFilename: String? {
        didSet { updateFilenameInUserDefaults(filename: customStartSoundFilename, for: .start) }
    }

    private var customStopSoundFilename: String? {
        didSet { updateFilenameInUserDefaults(filename: customStopSoundFilename, for: .stop) }
    }
    
    private func updateFilenameInUserDefaults(filename: String?, for type: RomaCustomSoundType) {
        RomaCustomSoundPreference.saveCustomFilename(filename, for: type)
    }

    private init() {
        let startState = RomaCustomSoundPreference.selectionState(for: .start)
        let stopState = RomaCustomSoundPreference.selectionState(for: .stop)
        self.isUsingCustomStartSound = startState.isUsingCustomSound
        self.isUsingCustomStopSound = stopState.isUsingCustomSound
        self.selectedStartBuiltInSound = startState.selectedBuiltInSound
        self.selectedStopBuiltInSound = stopState.selectedBuiltInSound
        self.customStartSoundFilename = startState.customFilename
        self.customStopSoundFilename = stopState.customFilename

        createCustomSoundsDirectoryIfNeeded()
    }

    private func customSoundsDirectory() -> URL? {
        RomaMacOSStorageDirectories.customSoundsDirectory
    }

    private func createCustomSoundsDirectoryIfNeeded() {
        guard let directory = customSoundsDirectory() else { return }

        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func getCustomSoundURL(for type: RomaCustomSoundType) -> URL? {
        customSoundSelectionState(for: type).customSoundURL(in: customSoundsDirectory())
    }

    func builtInSoundURL(for type: RomaCustomSoundType) -> URL? {
        selectedBuiltInSound(for: type).bundleURL
    }

    func selectedBuiltInSound(for type: RomaCustomSoundType) -> RomaBuiltInRecordingSound {
        customSoundSelectionState(for: type).selectedBuiltInSound
    }

    func isUsingCustomSound(for type: RomaCustomSoundType) -> Bool {
        customSoundSelectionState(for: type).isUsingCustomSound
    }

    func menuSelection(for type: RomaCustomSoundType) -> RomaCustomSoundMenuSelection {
        customSoundSelectionState(for: type).menuSelection
    }

    func selectBuiltInSound(_ sound: RomaBuiltInRecordingSound, for type: RomaCustomSoundType) {
        applyCustomSoundSelectionState(
            customSoundSelectionState(for: type).selectingBuiltInSound(sound)
        )
        notifyCustomSoundsChanged()
    }

    func useCustomSound(for type: RomaCustomSoundType) {
        guard let state = customSoundSelectionState(for: type).usingExistingCustomSound() else { return }
        applyCustomSoundSelectionState(state)
        notifyCustomSoundsChanged()
    }

    func setCustomSound(url: URL, for type: RomaCustomSoundType) -> Result<Void, RomaCustomSoundError> {
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

    func resetSoundToDefault(for type: RomaCustomSoundType) {
        let currentState = customSoundSelectionState(for: type)

        if let fileURL = currentState.storedCustomSoundURL(in: customSoundsDirectory()) {
            try? FileManager.default.removeItem(at: fileURL)
        }

        applyCustomSoundSelectionState(currentState.resettingToDefault())
        notifyCustomSoundsChanged()
    }

    private func notifyCustomSoundsChanged() {
        NotificationCenter.default.post(
            name: NSNotification.Name(RomaCustomSoundPreference.changedNotificationName),
            object: nil
        )
    }

    func getSoundDisplayName(for type: RomaCustomSoundType) -> String? {
        customSoundSelectionState(for: type).customFilename
    }

    func isDefaultSelection(for type: RomaCustomSoundType) -> Bool {
        customSoundSelectionState(for: type).isDefaultSelection
    }

    private func customSoundSelectionState(
        for type: RomaCustomSoundType
    ) -> RomaCustomSoundSelectionState {
        switch type {
        case .start:
            return RomaCustomSoundSelectionState(
                type: type,
                isUsingCustomSound: isUsingCustomStartSound,
                selectedBuiltInSound: selectedStartBuiltInSound,
                customFilename: customStartSoundFilename
            )
        case .stop:
            return RomaCustomSoundSelectionState(
                type: type,
                isUsingCustomSound: isUsingCustomStopSound,
                selectedBuiltInSound: selectedStopBuiltInSound,
                customFilename: customStopSoundFilename
            )
        }
    }

    private func applyCustomSoundSelectionState(_ state: RomaCustomSoundSelectionState) {
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

    private func copySoundFile(from sourceURL: URL, for type: RomaCustomSoundType) -> Result<String, RomaCustomSoundError> {
        guard let directory = customSoundsDirectory() else {
            return .failure(.directoryCreationFailed)
        }

        let copyPlan = RomaCustomSoundPreference.copyPlan(
            sourceURL: sourceURL,
            customSoundsDirectory: directory,
            for: type
        )

        return copyPlan.applyRuntimeState(
            removeExistingDestination: { try FileManager.default.removeItem(at: $0) },
            copyToDestination: { try FileManager.default.copyItem(at: sourceURL, to: $0) }
        )
    }

    private func validateAudioFile(url: URL) -> Result<Void, RomaCustomSoundError> {
        let fileExists = FileManager.default.fileExists(atPath: url.path)
        guard fileExists else {
            return .failure(
                RomaCustomSoundPreference.preflightValidationError(fileExists: false, duration: 0) ?? .fileNotFound
            )
        }

        let asset = AVAsset(url: url)
        let duration = asset.duration.seconds

        if let error = RomaCustomSoundPreference.preflightValidationError(
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
