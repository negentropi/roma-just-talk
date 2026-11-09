import AVFoundation
import os
import VoiceInkCore

/// After a recording that produced no words, asks whether the right microphone is selected and lets
/// the user switch right there, so a muted or wrong input does not look like Roma doing nothing.
@MainActor
enum MicrophoneCheckPrompt {
    private static let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "MicrophoneCheck")

    /// Call before the recording is deleted.
    static func showIfNeeded(audioURL: URL) async {
        guard let level = await AudioLevel.measure(audioURL) else { return }
        let finding = VoiceInkMicrophoneCheck.finding(durationSeconds: level.seconds, peakDecibels: level.peakDecibels)
        logger.notice("Empty recording seconds=\(level.seconds, privacy: .public) peakDb=\(level.peakDecibels, privacy: .public) finding=\(String(describing: finding), privacy: .public)")
        guard let finding else { return }

        let devices = AudioDeviceManager.shared
        let deviceID = devices.getCurrentDevice()
        let deviceName = devices.availableDevices.first { $0.id == deviceID }?.name ?? "this microphone"
        let systemDefault = devices.inputMode == .systemDefault
        var items = [NotificationMenu.Item(id: "system-default", title: VoiceInkMicrophoneCheck.systemDefaultTitle, isSelected: systemDefault) {
            devices.selectInputMode(.systemDefault)
        }]
        items += devices.availableDevices.map { device in
            NotificationMenu.Item(id: device.uid, title: device.name, isSelected: !systemDefault && device.id == deviceID) {
                devices.selectDeviceAndSwitchToCustomMode(id: device.id)
            }
        }
        NotificationManager.shared.showNotification(
            title: VoiceInkMicrophoneCheck.message(for: finding, deviceName: deviceName),
            type: .warning,
            duration: VoiceInkMicrophoneCheck.promptDuration,
            menu: NotificationMenu(label: VoiceInkMicrophoneCheck.changeMicrophoneLabel, items: items)
        )
    }
}

private enum AudioLevel {
    /// Length and loudest sample of a recording, read off the main thread.
    static func measure(_ url: URL) async -> (seconds: Double, peakDecibels: Float)? {
        await Task.detached(priority: .utility) { () -> (Double, Float)? in
            guard let file = try? AVAudioFile(forReading: url),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_384) else { return nil }
            var peak: Float = 0
            while (try? file.read(into: buffer)) != nil, buffer.frameLength > 0, let channels = buffer.floatChannelData {
                for channel in 0..<Int(buffer.format.channelCount) {
                    for frame in 0..<Int(buffer.frameLength) { peak = max(peak, abs(channels[channel][frame])) }
                }
            }
            let seconds = Double(file.length) / file.fileFormat.sampleRate
            return (seconds, 20 * log10(max(peak, 0.000_000_1)))
        }.value
    }
}
