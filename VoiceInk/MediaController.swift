import Foundation
import CoreAudio
import VoiceInkCore

final class MediaController: ObservableObject {

    static let shared = MediaController()

    private var mutedOutputDeviceID: AudioDeviceID?
    private var unmuteTask: Task<Void, Never>?
    private var muteGeneration: Int = 0

    @Published var systemMuteMode: VoiceInkSystemMuteMode = VoiceInkRecordingFeedbackPreference.systemMuteMode() {
        didSet {
            VoiceInkRecordingFeedbackPreference.saveSystemMuteMode(systemMuteMode)
        }
    }

    var isSystemMuteEnabled: Bool {
        get { systemMuteMode != .never }
        set { systemMuteMode = newValue ? .always : .never }
    }

    @Published var audioResumptionDelay: Double = VoiceInkRecordingFeedbackPreference.audioResumptionDelay() {
        didSet {
            VoiceInkRecordingFeedbackPreference.saveAudioResumptionDelay(audioResumptionDelay)
        }
    }

    private init() {}

    func muteSystemAudio() async -> Bool {
        guard let outputDeviceID = getDefaultOutputDevice(),
              shouldMuteAudio(forOutputDevice: outputDeviceID) else {
            return false
        }

        unmuteTask?.cancel()
        unmuteTask = nil
        muteGeneration += 1

        if let previousDeviceID = mutedOutputDeviceID,
           previousDeviceID != outputDeviceID {
            _ = setSystemMuted(false, on: previousDeviceID)
            mutedOutputDeviceID = nil
        }

        if isSystemAudioMuted(on: outputDeviceID) {
            return true
        }

        let success = setSystemMuted(true, on: outputDeviceID)
        mutedOutputDeviceID = success ? outputDeviceID : nil
        return success
    }

    func unmuteSystemAudio() async {
        guard let outputDeviceID = mutedOutputDeviceID else { return }

        let delay = audioResumptionDelay
        let myGeneration = muteGeneration

        let task = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            guard let self = self else { return }
            guard !Task.isCancelled else { return }
            guard self.muteGeneration == myGeneration else { return }

            _ = self.setSystemMuted(false, on: outputDeviceID)
            self.mutedOutputDeviceID = nil
        }

        unmuteTask = task
        await task.value
    }

    private func getDefaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )

        return status == noErr ? deviceID : nil
    }

    private func isSystemAudioMuted(on deviceID: AudioDeviceID) -> Bool {
        var muted: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if !AudioObjectHasProperty(deviceID, &address) {
            address.mElement = 0
            if !AudioObjectHasProperty(deviceID, &address) { return false }
        }

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, &muted)
        return status == noErr && muted != 0
    }

    private func setSystemMuted(_ muted: Bool, on deviceID: AudioDeviceID) -> Bool {
        var muteValue: UInt32 = muted ? 1 : 0
        let propertySize = UInt32(MemoryLayout<UInt32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if !AudioObjectHasProperty(deviceID, &address) {
            address.mElement = 0
            if !AudioObjectHasProperty(deviceID, &address) { return false }
        }

        var isSettable: DarwinBoolean = false
        var status = AudioObjectIsPropertySettable(deviceID, &address, &isSettable)
        if status != noErr || !isSettable.boolValue { return false }

        status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, propertySize, &muteValue)
        return status == noErr
    }

    private func shouldMuteAudio(forOutputDevice deviceID: AudioDeviceID) -> Bool {
        Self.shouldMuteAudio(
            mode: systemMuteMode,
            outputDeviceModelName: AudioDeviceManager.shared.getDeviceModelName(deviceID: deviceID),
            outputDeviceName: AudioDeviceManager.shared.getDeviceName(deviceID: deviceID)
        )
    }

    static func shouldMuteAudio(
        mode: VoiceInkSystemMuteMode,
        outputDeviceModelName: String?,
        outputDeviceName: String?
    ) -> Bool {
        switch mode {
        case .always:
            return true
        case .never:
            return false
        case .automatic:
            // ponytail: CoreAudio has no public AirPods type; add a product-ID catalog only if renamed devices become a real case.
            let outputIdentity = outputDeviceModelName ?? outputDeviceName
            return outputIdentity?.localizedCaseInsensitiveContains("airpods") != true
        }
    }
}
