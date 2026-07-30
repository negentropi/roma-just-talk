import CoreAudio
import Foundation
import RuntimeE2ECore

final class RuntimeSystemOutputSession {
    static let journalURL = URL(fileURLWithPath: "/tmp/roma-runtime-e2e-output-restoration.json")

    private let journal: RuntimeSystemOutputJournal
    private var restored = false

    private init(journal: RuntimeSystemOutputJournal) {
        self.journal = journal
    }

    static func start(targetDevice: RuntimeAudioDevice) throws -> RuntimeSystemOutputSession {
        if FileManager.default.fileExists(atPath: journalURL.path) {
            try restoreFromJournal()
        }
        let devices = try RuntimeAudioDeviceCatalog.devices()
        let currentID = try defaultOutputDeviceID()
        guard let current = devices.first(where: { $0.id == currentID }) else {
            throw RuntimeSystemOutputError.currentDeviceMissing
        }
        let originalTargetControlState = try deviceControlState(deviceID: targetDevice.id)
        let journal = RuntimeSystemOutputJournal(
            originalDeviceUID: current.uid,
            targetDeviceUID: targetDevice.uid,
            targetControlState: originalTargetControlState
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(journal).write(to: journalURL, options: .atomic)

        do {
            try setDefaultOutputDeviceID(targetDevice.id)
            let preparedState = originalTargetControlState.preparedForPlayback
            try setDeviceControlState(preparedState, deviceID: targetDevice.id)
            let actualState = try deviceControlState(deviceID: targetDevice.id)
            guard controlState(actualState, matches: preparedState) else {
                throw RuntimeSystemOutputError.deviceControlsNotPrepared(targetDevice.uid)
            }
        } catch {
            do {
                try restore(journal: journal)
                try? FileManager.default.removeItem(at: journalURL)
            } catch {
                // Keep the crash journal when rollback is incomplete.
            }
            throw error
        }
        return RuntimeSystemOutputSession(journal: journal)
    }

    func restore() throws {
        guard !restored else { return }
        try Self.restore(journal: journal)
        restored = true
        try? FileManager.default.removeItem(at: Self.journalURL)
    }

    static func restoreFromJournal() throws {
        let data = try Data(contentsOf: journalURL)
        let journal = try JSONDecoder().decode(RuntimeSystemOutputJournal.self, from: data)
        try restore(journal: journal)
        try FileManager.default.removeItem(at: journalURL)
    }

    private static func restore(journal: RuntimeSystemOutputJournal) throws {
        let devices = try RuntimeAudioDeviceCatalog.devices()
        var restorationError: Error?

        if let targetDeviceUID = journal.targetDeviceUID,
           let targetControlState = journal.targetControlState {
            if let targetDevice = devices.first(where: { $0.uid == targetDeviceUID }) {
                do {
                    try setDeviceControlState(targetControlState, deviceID: targetDevice.id)
                } catch {
                    restorationError = error
                }
            } else {
                restorationError = RuntimeSystemOutputError.targetDeviceMissing(targetDeviceUID)
            }
        }

        if let originalDevice = devices.first(where: { $0.uid == journal.originalDeviceUID }) {
            do {
                try setDefaultOutputDeviceID(originalDevice.id)
            } catch {
                restorationError = restorationError ?? error
            }
        } else {
            restorationError = restorationError
                ?? RuntimeSystemOutputError.originalDeviceMissing(journal.originalDeviceUID)
        }

        if let restorationError {
            throw restorationError
        }
    }

    private static func defaultOutputDeviceID() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != 0 else {
            throw RuntimeSystemOutputError.osStatus(status)
        }
        return deviceID
    }

    private static func setDefaultOutputDeviceID(_ deviceID: AudioDeviceID) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var mutableDeviceID = deviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &mutableDeviceID
        )
        guard status == noErr else {
            throw RuntimeSystemOutputError.osStatus(status)
        }
    }

    private static func deviceControlState(
        deviceID: AudioDeviceID
    ) throws -> RuntimeLoopbackDeviceControlState {
        RuntimeLoopbackDeviceControlState(
            inputMuted: try mute(deviceID: deviceID, scope: kAudioDevicePropertyScopeInput),
            outputMuted: try mute(deviceID: deviceID, scope: kAudioDevicePropertyScopeOutput),
            inputVolume: try volume(deviceID: deviceID, scope: kAudioDevicePropertyScopeInput),
            outputVolume: try volume(deviceID: deviceID, scope: kAudioDevicePropertyScopeOutput)
        )
    }

    private static func setDeviceControlState(
        _ state: RuntimeLoopbackDeviceControlState,
        deviceID: AudioDeviceID
    ) throws {
        try setMute(state.inputMuted, deviceID: deviceID, scope: kAudioDevicePropertyScopeInput)
        try setMute(state.outputMuted, deviceID: deviceID, scope: kAudioDevicePropertyScopeOutput)
        try setVolume(state.inputVolume, deviceID: deviceID, scope: kAudioDevicePropertyScopeInput)
        try setVolume(state.outputVolume, deviceID: deviceID, scope: kAudioDevicePropertyScopeOutput)
    }

    private static func mute(
        deviceID: AudioDeviceID,
        scope: AudioObjectPropertyScope
    ) throws -> Bool? {
        var address = controlAddress(selector: kAudioDevicePropertyMute, scope: scope)
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr else {
            throw RuntimeSystemOutputError.osStatus(status)
        }
        return value != 0
    }

    private static func volume(
        deviceID: AudioDeviceID,
        scope: AudioObjectPropertyScope
    ) throws -> Double? {
        var address = controlAddress(selector: kAudioDevicePropertyVolumeScalar, scope: scope)
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr else {
            throw RuntimeSystemOutputError.osStatus(status)
        }
        return Double(value)
    }

    private static func setMute(
        _ muted: Bool?,
        deviceID: AudioDeviceID,
        scope: AudioObjectPropertyScope
    ) throws {
        guard let muted else { return }
        var address = controlAddress(selector: kAudioDevicePropertyMute, scope: scope)
        var value: UInt32 = muted ? 1 : 0
        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &value
        )
        guard status == noErr else {
            throw RuntimeSystemOutputError.osStatus(status)
        }
    }

    private static func setVolume(
        _ volume: Double?,
        deviceID: AudioDeviceID,
        scope: AudioObjectPropertyScope
    ) throws {
        guard let volume else { return }
        var address = controlAddress(selector: kAudioDevicePropertyVolumeScalar, scope: scope)
        var value = Float32(volume)
        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &value
        )
        guard status == noErr else {
            throw RuntimeSystemOutputError.osStatus(status)
        }
    }

    private static func controlAddress(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func controlState(
        _ actual: RuntimeLoopbackDeviceControlState,
        matches expected: RuntimeLoopbackDeviceControlState
    ) -> Bool {
        guard actual.inputMuted == expected.inputMuted,
              actual.outputMuted == expected.outputMuted else {
            return false
        }
        return volume(actual.inputVolume, matches: expected.inputVolume)
            && volume(actual.outputVolume, matches: expected.outputVolume)
    }

    private static func volume(_ actual: Double?, matches expected: Double?) -> Bool {
        switch (actual, expected) {
        case (nil, nil):
            return true
        case let (actual?, expected?):
            return abs(actual - expected) <= 0.001
        default:
            return false
        }
    }
}

enum RuntimeSystemOutputError: Error, CustomStringConvertible {
    case currentDeviceMissing
    case originalDeviceMissing(String)
    case targetDeviceMissing(String)
    case deviceControlsNotPrepared(String)
    case osStatus(OSStatus)

    var description: String {
        switch self {
        case .currentDeviceMissing:
            return "Current default output device is missing from CoreAudio catalog"
        case .originalDeviceMissing(let uid):
            return "Original output device is unavailable: \(uid)"
        case .targetDeviceMissing(let uid):
            return "Loopback device is unavailable during restoration: \(uid)"
        case .deviceControlsNotPrepared(let uid):
            return "Loopback mute/volume controls did not reach playback state: \(uid)"
        case .osStatus(let status):
            return "CoreAudio output-device operation failed (OSStatus \(status))"
        }
    }
}
