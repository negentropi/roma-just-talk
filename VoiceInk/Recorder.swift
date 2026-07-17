import Foundation
import AVFoundation
import CoreAudio
import os
import VoiceInkCore

@MainActor
class Recorder: NSObject, ObservableObject {
    private var recorder: CoreAudioRecorder? = CoreAudioRecorder()
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "Recorder")
    private let deviceManager = AudioDeviceManager.shared
    private var deviceSwitchObserver: NSObjectProtocol?
    private var audioDeviceChangeObserver: NSObjectProtocol?
    private var isReconfiguring = false
    private let mediaController = MediaController.shared
    private let playbackController = PlaybackController.shared
    @Published var audioMeter = AudioMeter(averagePower: 0, peakPower: 0)
    private var audioMeterUpdateTimer: DispatchSourceTimer?
    private let audioMeterQueue = DispatchQueue(label: "\(VoiceInkAppIdentity.loggingSubsystem).audiometer", qos: .userInteractive)
    /// Dedicated serial queue for hardware setup.
    private let audioSetupQueue = DispatchQueue(label: "\(VoiceInkAppIdentity.loggingSubsystem).audioSetup", qos: .userInitiated)
    private var audioMuteTask: Task<Void, Never>?
    private var audioRestorationTask: Task<Void, Never>?
    private let smoothedValuesLock = NSLock()
    private var smoothedAverage: Float = 0
    private var smoothedPeak: Float = 0

    /// Audio chunk callback for streaming. Can be updated while recording;
    /// changes are forwarded to the live CoreAudioRecorder.
    var onAudioChunk: ((_ data: Data) -> Void)? {
        didSet { recorder?.onAudioChunk = onAudioChunk }
    }

    enum RecorderError: Error {
        case couldNotStartRecording
    }
    
    override init() {
        super.init()
        setupDeviceSwitchObserver()
    }

    private func setupDeviceSwitchObserver() {
        deviceSwitchObserver = NotificationCenter.default.addObserver(
            forName: .audioDeviceSwitchRequired,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task {
                await self?.handleDeviceSwitchRequired(notification)
            }
        }

        audioDeviceChangeObserver = NotificationCenter.default.addObserver(
            forName: .audioDeviceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleAudioDeviceChanged()
            }
        }
    }

    private func handleAudioDeviceChanged() async {
        guard !deviceManager.isRecordingActive else { return }
        await startPreRollBuffering()
    }

    private func handleDeviceSwitchRequired(_ notification: Notification) async {
        guard !isReconfiguring else { return }
        guard let recorder = recorder else { return }
        guard let newDeviceID = VoiceInkMacOSAudioDeviceChangeRequest.newDeviceID(from: notification) else {
            logger.error("Device switch notification missing newDeviceID")
            return
        }

        // Prevent concurrent device switches and handleDeviceChange() interference
        isReconfiguring = true
        defer { isReconfiguring = false }

        logger.notice("🎙️ Device switch required: switching to device \(newDeviceID, privacy: .public)")

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                audioSetupQueue.async {
                    do {
                        try recorder.switchDevice(to: newDeviceID)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            // Notify user about the switch
            if let deviceName = deviceManager.availableDevices.first(where: { $0.id == newDeviceID })?.name {
                await MainActor.run {
                    NotificationManager.shared.showNotification(
                        title: VoiceInkMacOSAudioInputSettingsPresentation.macOS.switchedDeviceNotificationTitle(
                            deviceName: deviceName
                        ),
                        type: .info
                    )
                }
            }

            logger.notice("🎙️ Successfully switched recording to device \(newDeviceID, privacy: .public)")
        } catch {
            logger.error("❌ Failed to switch device: \(error.localizedDescription, privacy: .public)")

            // If switch fails, stop recording and notify user
            await handleRecordingError(error)
        }
    }

    func scheduleSystemMute(
        forInputDevice deviceID: AudioDeviceID,
        afterDelayNanoseconds delay: UInt64 = VoiceInkRecordingFeedbackPreference.defaultSystemMuteScheduleDelayNanoseconds
    ) {
        audioMuteTask?.cancel()
        audioMuteTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self else { return }
            _ = await self.mediaController.muteSystemAudio(forInputDevice: deviceID)
        }
    }

    func startPreRollBuffering() async {
        guard !deviceManager.isRecordingActive else { return }

        let deviceID = deviceManager.getCurrentDevice()
        guard deviceID != 0 else {
            logger.error("startPreRollBuffering: no available input device")
            return
        }

        let coreAudioRecorder = recorder ?? CoreAudioRecorder()
        recorder = coreAudioRecorder
        coreAudioRecorder.onAudioChunk = nil

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                audioSetupQueue.async {
                    do {
                        try coreAudioRecorder.startPreBuffering(deviceID: deviceID)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            logger.notice("startPreRollBuffering: active on deviceID=\(deviceID, privacy: .public)")
        } catch {
            logger.error("startPreRollBuffering failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func startRecording(toOutputFile url: URL) async throws {
        logger.notice("startRecording called – deviceID=\(self.deviceManager.getCurrentDevice(), privacy: .public), file=\(url.lastPathComponent, privacy: .public)")
        deviceManager.isRecordingActive = true

        let currentDeviceID = deviceManager.getCurrentDevice()
        let currentDeviceIdentifier = String(currentDeviceID)
        if VoiceInkAudioInputPreference.shouldAnnounceMicrophoneChange(to: currentDeviceIdentifier) {
            if let deviceName = deviceManager.availableDevices.first(where: { $0.id == currentDeviceID })?.name {
                NotificationManager.shared.showNotification(
                    title: VoiceInkMacOSAudioInputSettingsPresentation.macOS.usingDeviceNotificationTitle(
                        deviceName: deviceName
                    ),
                    type: .info
                )
            }
        }
        VoiceInkAudioInputPreference.saveLastUsedMicrophoneDeviceID(currentDeviceIdentifier)

        let deviceID = currentDeviceID

        audioRestorationTask?.cancel()
        audioRestorationTask = nil
        audioMeterUpdateTimer?.cancel()
        scheduleSystemMute(forInputDevice: deviceID)

        let coreAudioRecorder = recorder ?? CoreAudioRecorder()
        coreAudioRecorder.onAudioChunk = onAudioChunk
        recorder = coreAudioRecorder

        do {
            // Offload initialization to avoid shortcut lag.
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                audioSetupQueue.async {
                    do {
                        try coreAudioRecorder.startRecording(toOutputFile: url, deviceID: deviceID)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            logger.notice("startRecording: CoreAudioRecorder started successfully")

            startAudioMeterTimer()
            Task { [weak self] in
                guard let self else { return }
                await self.playbackController.pauseMedia()
            }
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription, privacy: .public)")
            await stopRecording()
            throw RecorderError.couldNotStartRecording
        }
    }

    func stopRecording() async {
        logger.notice("stopRecording called")
        audioMuteTask?.cancel()
        audioMuteTask = nil
        audioMeterUpdateTimer?.cancel()
        audioMeterUpdateTimer = nil

        let currentRecorder = self.recorder
        await withCheckedContinuation { continuation in
            audioSetupQueue.async {
                currentRecorder?.finishRecording()
                currentRecorder?.onAudioChunk = nil
                continuation.resume()
            }
        }
        onAudioChunk = nil

        smoothedValuesLock.lock()
        smoothedAverage = 0
        smoothedPeak = 0
        smoothedValuesLock.unlock()

        audioMeter = AudioMeter(averagePower: 0, peakPower: 0)

        audioRestorationTask = Task {
            await mediaController.unmuteSystemAudio()
            await playbackController.resumeMedia()
        }
        deviceManager.isRecordingActive = false
    }

    private func handleRecordingError(_ error: Error) async {
        logger.error("❌ Recording error occurred: \(error.localizedDescription, privacy: .public)")

        // Stop the recording
        await stopRecording()

        // Notify the user about the recording failure
        await MainActor.run {
            NotificationManager.shared.showNotification(
                title: VoiceInkRecordingNotificationPresentation.runtimeFailure(
                    localizedDescription: error.localizedDescription
                ).title,
                type: .error
            )
        }
    }

    private func startAudioMeterTimer() {
        let timer = DispatchSource.makeTimerSource(queue: audioMeterQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(VoiceInkAudioMeterLevel.macOSUpdateIntervalMilliseconds))
        timer.setEventHandler { [weak self] in
            self?.updateAudioMeter()
        }
        timer.resume()
        audioMeterUpdateTimer = timer
    }

    private func updateAudioMeter() {
        guard let recorder = recorder else { return }

        // Sample audio levels (thread-safe read)
        let averagePower = recorder.averagePower
        let peakPower = recorder.peakPower

        // Apply EMA smoothing with thread-safe access
        smoothedValuesLock.lock()
        let meterPlan = VoiceInkAudioMeterLevel.macOSMeterUpdatePlan(
            averageDecibels: averagePower,
            peakDecibels: peakPower,
            previousSmoothedAverage: smoothedAverage,
            previousSmoothedPeak: smoothedPeak
        )
        smoothedAverage = meterPlan.smoothedAverage
        smoothedPeak = meterPlan.smoothedPeak
        let newAudioMeter = AudioMeter(averagePower: Double(smoothedAverage), peakPower: Double(smoothedPeak))
        smoothedValuesLock.unlock()

        // Dispatch to main queue for UI updates (more efficient than Task)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.audioMeter = newAudioMeter
        }
    }
    
    // MARK: - Cleanup

    deinit {
        audioMeterUpdateTimer?.cancel()
        audioRestorationTask?.cancel()
        if let observer = deviceSwitchObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = audioDeviceChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        recorder?.stopRecording()
    }
}

struct AudioMeter: Equatable {
    let averagePower: Double
    let peakPower: Double
}
