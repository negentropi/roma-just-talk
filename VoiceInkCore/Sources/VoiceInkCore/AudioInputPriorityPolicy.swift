import Foundation

public struct VoiceInkAudioInputPriorityDevice: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let priority: Int

    public init(id: String, name: String, priority: Int) {
        self.id = id
        self.name = name
        self.priority = priority
    }
}

public enum VoiceInkAudioInputPriorityMoveDirection: Equatable, Sendable {
    case up
    case down
}

public enum VoiceInkAudioInputPriorityPolicy {
    public static func sortedDevices(
        _ devices: [VoiceInkAudioInputPriorityDevice]
    ) -> [VoiceInkAudioInputPriorityDevice] {
        devices.sorted { $0.priority < $1.priority }
    }

    public static func reindexed(
        _ devices: [VoiceInkAudioInputPriorityDevice]
    ) -> [VoiceInkAudioInputPriorityDevice] {
        devices.enumerated().map { index, device in
            VoiceInkAudioInputPriorityDevice(id: device.id, name: device.name, priority: index)
        }
    }

    public static func addDevice(
        uid: String,
        name: String,
        to devices: [VoiceInkAudioInputPriorityDevice]
    ) -> [VoiceInkAudioInputPriorityDevice] {
        guard !devices.contains(where: { $0.id == uid }) else {
            return devices
        }

        let nextPriority = (devices.map(\.priority).max() ?? -1) + 1
        return devices + [
            VoiceInkAudioInputPriorityDevice(id: uid, name: name, priority: nextPriority)
        ]
    }

    public static func removeDevice(
        id: String,
        from devices: [VoiceInkAudioInputPriorityDevice]
    ) -> [VoiceInkAudioInputPriorityDevice] {
        reindexed(devices.filter { $0.id != id })
    }

    public static func moveDevice(
        id: String,
        direction: VoiceInkAudioInputPriorityMoveDirection,
        in devices: [VoiceInkAudioInputPriorityDevice]
    ) -> [VoiceInkAudioInputPriorityDevice] {
        guard let currentIndex = devices.firstIndex(where: { $0.id == id }) else {
            return devices
        }

        let targetIndex: Int
        switch direction {
        case .up:
            targetIndex = currentIndex - 1
        case .down:
            targetIndex = currentIndex + 1
        }

        guard devices.indices.contains(targetIndex) else {
            return devices
        }

        var movedDevices = devices
        movedDevices.swapAt(currentIndex, targetIndex)
        return reindexed(movedDevices)
    }

    public static func firstAvailablePriorityDeviceID(
        in devices: [VoiceInkAudioInputPriorityDevice],
        availableDeviceIDs: Set<String>
    ) -> String? {
        sortedDevices(devices).first { availableDeviceIDs.contains($0.id) }?.id
    }
}
