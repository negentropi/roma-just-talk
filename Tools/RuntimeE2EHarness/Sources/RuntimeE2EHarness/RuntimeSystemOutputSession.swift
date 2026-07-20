import CoreAudio
import Foundation

private struct RuntimeSystemOutputJournal: Codable {
    let originalDeviceUID: String
}

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
        let journal = RuntimeSystemOutputJournal(originalDeviceUID: current.uid)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(journal).write(to: journalURL, options: .atomic)

        do {
            try setDefaultOutputDeviceID(targetDevice.id)
        } catch {
            try? restore(journal: journal)
            try? FileManager.default.removeItem(at: journalURL)
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
        guard let device = devices.first(where: { $0.uid == journal.originalDeviceUID }) else {
            throw RuntimeSystemOutputError.originalDeviceMissing(journal.originalDeviceUID)
        }
        try setDefaultOutputDeviceID(device.id)
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
}

enum RuntimeSystemOutputError: Error, CustomStringConvertible {
    case currentDeviceMissing
    case originalDeviceMissing(String)
    case osStatus(OSStatus)

    var description: String {
        switch self {
        case .currentDeviceMissing:
            return "Current default output device is missing from CoreAudio catalog"
        case .originalDeviceMissing(let uid):
            return "Original output device is unavailable: \(uid)"
        case .osStatus(let status):
            return "CoreAudio output-device operation failed (OSStatus \(status))"
        }
    }
}
