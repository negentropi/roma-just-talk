import AVFoundation
import AudioToolbox
import CoreAudio
import Darwin
import Foundation

enum PlaybackError: Error, CustomStringConvertible {
    case usage
    case coreAudio(String, OSStatus)
    case deviceNotFound(String)
    case missingOutputUnit
    case invalidDuration(String)
    case mixerProducedNoSamples
    case playbackDidNotStart
    case playbackTimedOut

    var description: String {
        switch self {
        case .usage:
            return "usage: roma-play-wav <device-uid> <wav-path> [seconds]"
        case let .coreAudio(operation, status):
            return "\(operation) failed with CoreAudio status \(status)"
        case let .deviceNotFound(uid):
            return "no CoreAudio device has UID \(uid)"
        case .missingOutputUnit:
            return "AVAudioEngine did not expose an output AudioUnit"
        case let .invalidDuration(value):
            return "invalid playback duration: \(value)"
        case .mixerProducedNoSamples:
            return "AVAudioEngine rendered no mixer samples"
        case .playbackDidNotStart:
            return "CoreAudio did not play the first WAV frame before its deadline"
        case .playbackTimedOut:
            return "CoreAudio playback did not finish before its deadline"
        }
    }
}

final class AudioMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: Double = 0
    private var sampleCount = 0
    private var squaredTotal: Double = 0

    func consume(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        lock.lock()
        defer { lock.unlock() }
        for channelIndex in 0 ..< Int(buffer.format.channelCount) {
            let samples = channels[channelIndex]
            for frameIndex in 0 ..< Int(buffer.frameLength) {
                let sample = Double(samples[frameIndex])
                squaredTotal += sample * sample
                peak = max(peak, abs(sample))
                sampleCount += 1
            }
        }
    }

    func decibelsFullScale() throws -> (rms: Double, peak: Double, sampleCount: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard sampleCount > 0 else { throw PlaybackError.mixerProducedNoSamples }
        let rms = sqrt(squaredTotal / Double(sampleCount))
        return (
            rms > 0 ? 20 * log10(rms) : -.infinity,
            peak > 0 ? 20 * log10(peak) : -.infinity,
            sampleCount
        )
    }
}

func continuousNanoseconds() -> UInt64 {
    let ticks = mach_continuous_time()
    var timebase = mach_timebase_info_data_t()
    precondition(mach_timebase_info(&timebase) == KERN_SUCCESS)
    return UInt64(
        (Double(ticks) * Double(timebase.numer) / Double(timebase.denom)).rounded()
    )
}

struct PlaybackTimestamp {
    let continuousNanoseconds: UInt64
    let epochNanoseconds: UInt64
}

func playbackTimestamp() -> PlaybackTimestamp {
    let continuousBefore = continuousNanoseconds()
    var realtime = timespec()
    precondition(clock_gettime(CLOCK_REALTIME, &realtime) == 0)
    let epochNanoseconds = UInt64(realtime.tv_sec) * 1_000_000_000 + UInt64(realtime.tv_nsec)
    let continuousAfter = continuousNanoseconds()
    return PlaybackTimestamp(
        continuousNanoseconds: continuousBefore + (continuousAfter - continuousBefore) / 2,
        epochNanoseconds: epochNanoseconds
    )
}

final class PlaybackEventClock: @unchecked Sendable {
    private let lock = NSLock()
    private var timestamp: PlaybackTimestamp?

    func markPlayedBack() {
        lock.lock()
        defer { lock.unlock() }
        if timestamp == nil {
            timestamp = playbackTimestamp()
        }
    }

    func playedBackTimestamp() throws -> PlaybackTimestamp {
        lock.lock()
        defer { lock.unlock() }
        guard let timestamp else { throw PlaybackError.playbackDidNotStart }
        return timestamp
    }
}

func requireNoError(_ status: OSStatus, _ operation: String) throws {
    if status != noErr {
        throw PlaybackError.coreAudio(operation, status)
    }
}

func audioDeviceID(uid expectedUID: String) throws -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var qualifier: Unmanaged<CFString>? = Unmanaged.passUnretained(expectedUID as CFString)
    var device = AudioDeviceID(kAudioObjectUnknown)
    var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
    try requireNoError(
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<Unmanaged<CFString>?>.size),
            &qualifier,
            &dataSize,
            &device
        ),
        "translate output device UID"
    )
    if device == kAudioObjectUnknown {
        throw PlaybackError.deviceNotFound(expectedUID)
    }
    return device
}

func play(deviceUID: String, wavPath: String, maximumSeconds: Double?) throws {
    let deviceID = try audioDeviceID(uid: deviceUID)
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: wavPath))
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()

    guard let outputUnit = engine.outputNode.audioUnit else {
        throw PlaybackError.missingOutputUnit
    }
    var selectedDevice = deviceID
    try requireNoError(
        AudioUnitSetProperty(
            outputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &selectedDevice,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        ),
        "select output device"
    )
    func verifyBoundDevice(_ operation: String) throws {
        var boundDevice = AudioDeviceID(kAudioObjectUnknown)
        var boundDeviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        try requireNoError(
            AudioUnitGetProperty(
                outputUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &boundDevice,
                &boundDeviceSize
            ),
            operation
        )
        if boundDevice != deviceID {
            throw PlaybackError.deviceNotFound("\(deviceUID) resolved to \(deviceID), bound \(boundDevice)")
        }
    }
    try verifyBoundDevice("verify selected output device")
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)

    let meter = AudioMeter()
    engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1_024, format: nil) { buffer, _ in
        meter.consume(buffer)
    }

    let framesToPlay: AVAudioFramePosition
    if let maximumSeconds {
        framesToPlay = min(file.length, AVAudioFramePosition((maximumSeconds * file.fileFormat.sampleRate).rounded()))
    } else {
        framesToPlay = file.length
    }
    guard framesToPlay > 0, framesToPlay <= AVAudioFramePosition(UInt32.max) else {
        throw PlaybackError.invalidDuration(maximumSeconds.map { String($0) } ?? "file duration")
    }

    let started = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)
    let startClock = PlaybackEventClock()
    let finishClock = PlaybackEventClock()
    player.scheduleSegment(
        file,
        startingFrame: 0,
        frameCount: 1,
        at: nil,
        completionCallbackType: .dataPlayedBack
    ) { _ in
        startClock.markPlayedBack()
        started.signal()
        if framesToPlay == 1 {
            finishClock.markPlayedBack()
            finished.signal()
        }
    }
    if framesToPlay > 1 {
        player.scheduleSegment(
            file,
            startingFrame: 1,
            frameCount: AVAudioFrameCount(framesToPlay - 1),
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { _ in
            finishClock.markPlayedBack()
            finished.signal()
        }
    }
    try engine.start()
    defer {
        player.stop()
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()
    }
    try verifyBoundDevice("verify running output device")
    let playbackSeconds = Double(framesToPlay) / file.fileFormat.sampleRate
    player.play()
    guard started.wait(timeout: .now() + 5) == .success else {
        throw PlaybackError.playbackDidNotStart
    }
    let playedBackTimestamp = try startClock.playedBackTimestamp()
    FileHandle.standardOutput.write(Data(
        "started marker=first-frame-played-back callback_continuous_ns=\(playedBackTimestamp.continuousNanoseconds) callback_epoch_ns=\(playedBackTimestamp.epochNanoseconds) device_uid=\(deviceUID) device_id=\(deviceID) frames=\(framesToPlay) seconds=\(playbackSeconds)\n".utf8
    ))
    guard finished.wait(timeout: .now() + playbackSeconds + 5) == .success else {
        throw PlaybackError.playbackTimedOut
    }
    let finishedTimestamp = try finishClock.playedBackTimestamp()
    let mixerLevel = try meter.decibelsFullScale()
    print(
        "completed callback_continuous_ns=\(finishedTimestamp.continuousNanoseconds) callback_epoch_ns=\(finishedTimestamp.epochNanoseconds) device_uid=\(deviceUID) frames=\(framesToPlay) seconds=\(playbackSeconds) "
            + "mixer_rms_dbfs=\(mixerLevel.rms) mixer_peak_dbfs=\(mixerLevel.peak) mixer_samples=\(mixerLevel.sampleCount)"
    )
}

do {
    guard CommandLine.arguments.count == 3 || CommandLine.arguments.count == 4 else {
        throw PlaybackError.usage
    }
    let maximumSeconds: Double?
    if CommandLine.arguments.count == 4 {
        guard let parsed = Double(CommandLine.arguments[3]), parsed > 0 else {
            throw PlaybackError.invalidDuration(CommandLine.arguments[3])
        }
        maximumSeconds = parsed
    } else {
        maximumSeconds = nil
    }
    try play(
        deviceUID: CommandLine.arguments[1],
        wavPath: CommandLine.arguments[2],
        maximumSeconds: maximumSeconds
    )
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
