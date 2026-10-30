import Foundation
import AVFoundation
import CoreAudio
import Atomics
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
    private let microphoneCaptureEnabled = ManagedAtomic(
        VoiceInkLipDictationPreference.mode(in: .standard).usesMicrophone
    )
    private let microphoneCaptureGeneration = ManagedAtomic<UInt64>(0)
    private var audioMuteTask: Task<Void, Never>?
    private var audioRestorationTask: Task<Void, Never>?
    private var activeRecordingID: UUID?
    private var activeLatencyTraceToken: VoiceInkLatencyTrace.Token?
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
        guard microphoneCaptureEnabled.load(ordering: .acquiring), !deviceManager.isRecordingActive else { return }
        await startPreRollBuffering()
    }

    private func handleDeviceSwitchRequired(_ notification: Notification) async {
        guard microphoneCaptureEnabled.load(ordering: .acquiring) else { return }
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

        let captureEnabled = microphoneCaptureEnabled
        let captureGeneration = microphoneCaptureGeneration
        let generation = captureGeneration.load(ordering: .acquiring)
        let recordingID = activeRecordingID
        do {
            let switched = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                audioSetupQueue.async {
                    guard captureEnabled.load(ordering: .acquiring),
                          captureGeneration.load(ordering: .acquiring) == generation else {
                        continuation.resume(returning: false)
                        return
                    }
                    do {
                        try recorder.switchDevice(to: newDeviceID)
                        guard captureEnabled.load(ordering: .acquiring),
                              captureGeneration.load(ordering: .acquiring) == generation else {
                            recorder.stopRecording()
                            continuation.resume(returning: false)
                            return
                        }
                        continuation.resume(returning: true)
                    } catch {
                        guard captureEnabled.load(ordering: .acquiring),
                              captureGeneration.load(ordering: .acquiring) == generation else {
                            recorder.stopRecording()
                            continuation.resume(returning: false)
                            return
                        }
                        continuation.resume(throwing: error)
                    }
                }
            }
            guard switched, microphoneCaptureEnabled.load(ordering: .acquiring),
                  captureGeneration.load(ordering: .acquiring) == generation,
                  activeRecordingID == recordingID else { return }

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
            guard microphoneCaptureEnabled.load(ordering: .acquiring),
                  captureGeneration.load(ordering: .acquiring) == generation,
                  activeRecordingID == recordingID else { return }
            logger.error("❌ Failed to switch device: \(error.localizedDescription, privacy: .public)")

            // If switch fails, stop recording and notify user
            await handleRecordingError(error)
        }
    }

    func scheduleSystemMute(
        afterDelayNanoseconds delay: UInt64 = VoiceInkRecordingFeedbackPreference.defaultSystemMuteScheduleDelayNanoseconds
    ) {
        guard microphoneCaptureEnabled.load(ordering: .acquiring) else { return }
        // ponytail: Evaluate once per recording; observe route changes only if mid-recording switching matters.
        audioMuteTask?.cancel()
        audioMuteTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self,
                  self.microphoneCaptureEnabled.load(ordering: .acquiring) else { return }
            _ = await self.mediaController.muteSystemAudio()
        }
    }

    func setMicrophoneCaptureEnabled(_ enabled: Bool) async {
        if !enabled {
            microphoneCaptureGeneration.wrappingIncrement(ordering: .acquiringAndReleasing)
        }
        let wasEnabled = microphoneCaptureEnabled.exchange(enabled, ordering: .acquiringAndReleasing)
        if enabled {
            if !wasEnabled { await startPreRollBuffering() }
            return
        }

        audioMuteTask?.cancel()
        audioMuteTask = nil
        audioMeterUpdateTimer?.cancel()
        audioMeterUpdateTimer = nil
        onAudioChunk = nil
        activeRecordingID = nil
        deviceManager.isRecordingActive = false
        let currentRecorder = recorder
        // Advancing the generation also rejects old starts if permission is restored before they execute.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            audioSetupQueue.async {
                currentRecorder?.onAudioChunk = nil
                currentRecorder?.stopRecording()
                continuation.resume()
            }
        }
        if !microphoneCaptureEnabled.load(ordering: .acquiring) {
            audioMeter = AudioMeter(averagePower: 0, peakPower: 0)
        }
    }

    func microphoneCaptureStatus() async -> (isRecording: Bool, isPreBuffering: Bool, hasAudioUnit: Bool) {
        let currentRecorder = recorder
        return await withCheckedContinuation { continuation in
            audioSetupQueue.async {
                continuation.resume(returning: (
                    isRecording: currentRecorder?.isCurrentlyRecording ?? false,
                    isPreBuffering: currentRecorder?.isPreBuffering ?? false,
                    hasAudioUnit: currentRecorder?.hasAudioUnit ?? false
                ))
            }
        }
    }

    func startPreRollBuffering() async {
        guard microphoneCaptureEnabled.load(ordering: .acquiring), !deviceManager.isRecordingActive else { return }

        let deviceID = deviceManager.getCurrentDevice()
        guard deviceID != 0 else {
            logger.error("startPreRollBuffering: no available input device")
            return
        }

        let coreAudioRecorder = recorder ?? CoreAudioRecorder()
        recorder = coreAudioRecorder
        coreAudioRecorder.onAudioChunk = nil

        let captureEnabled = microphoneCaptureEnabled
        let captureGeneration = microphoneCaptureGeneration
        let generation = captureGeneration.load(ordering: .acquiring)
        do {
            let started = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                audioSetupQueue.async {
                    guard captureEnabled.load(ordering: .acquiring),
                          captureGeneration.load(ordering: .acquiring) == generation else {
                        continuation.resume(returning: false)
                        return
                    }
                    do {
                        try coreAudioRecorder.startPreBuffering(deviceID: deviceID)
                        guard captureEnabled.load(ordering: .acquiring),
                              captureGeneration.load(ordering: .acquiring) == generation else {
                            coreAudioRecorder.stopRecording()
                            continuation.resume(returning: false)
                            return
                        }
                        continuation.resume(returning: true)
                    } catch {
                        guard captureEnabled.load(ordering: .acquiring),
                              captureGeneration.load(ordering: .acquiring) == generation else {
                            coreAudioRecorder.stopRecording()
                            continuation.resume(returning: false)
                            return
                        }
                        continuation.resume(throwing: error)
                    }
                }
            }
            guard started, microphoneCaptureEnabled.load(ordering: .acquiring),
                  captureGeneration.load(ordering: .acquiring) == generation else { return }
            logger.notice("startPreRollBuffering: active on deviceID=\(deviceID, privacy: .public)")
        } catch {
            logger.error("startPreRollBuffering failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func startRecording(
        toOutputFile url: URL,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async throws {
        guard microphoneCaptureEnabled.load(ordering: .acquiring) else {
            throw RecorderError.couldNotStartRecording
        }
        let recordingID = UUID()
        activeRecordingID = recordingID
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken
        activeLatencyTraceToken = traceToken
        latencyTrace.event("recorder.start.enter", token: traceToken)
        logger.notice("startRecording called – deviceID=\(self.deviceManager.getCurrentDevice(), privacy: .public), file=\(url.lastPathComponent, privacy: .public)")
        deviceManager.isRecordingActive = true

        let deviceLookupSpan = latencyTrace.begin("recorder.device_lookup", token: traceToken)
        let currentDeviceID = deviceManager.getCurrentDevice()
        latencyTrace.end(deviceLookupSpan, details: "deviceID=\(currentDeviceID)")
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
        scheduleSystemMute()

        let coreAudioRecorder = recorder ?? CoreAudioRecorder()
        let audioChunkHandler = onAudioChunk
        recorder = coreAudioRecorder

        let captureEnabled = microphoneCaptureEnabled
        let captureGeneration = microphoneCaptureGeneration
        let generation = captureGeneration.load(ordering: .acquiring)
        do {
            // Offload initialization to avoid shortcut lag.
            latencyTrace.event("recorder.audio_setup_queue.schedule_start", token: traceToken)
            let startResumeCheckpoint = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<VoiceInkLatencyTrace.ExecutorCheckpoint?, Error>) in
                audioSetupQueue.async {
                    guard captureEnabled.load(ordering: .acquiring),
                          captureGeneration.load(ordering: .acquiring) == generation else {
                        continuation.resume(throwing: RecorderError.couldNotStartRecording)
                        return
                    }
                    let queueSpan = latencyTrace.begin("recorder.audio_setup_queue.start", token: traceToken)
                    do {
                        coreAudioRecorder.onAudioChunk = audioChunkHandler
                        try coreAudioRecorder.startRecording(
                            toOutputFile: url,
                            deviceID: deviceID,
                            latencyTraceToken: traceToken
                        )
                        guard captureEnabled.load(ordering: .acquiring),
                              captureGeneration.load(ordering: .acquiring) == generation else {
                            throw RecorderError.couldNotStartRecording
                        }
                        latencyTrace.end(queueSpan, details: "result=success")
                        let checkpoint = latencyTrace.executorEnqueued(
                            "recorder.audio_setup_queue.start_continuation",
                            token: traceToken
                        )
                        continuation.resume(returning: checkpoint)
                    } catch {
                        if !captureEnabled.load(ordering: .acquiring)
                            || captureGeneration.load(ordering: .acquiring) != generation {
                            coreAudioRecorder.stopRecording()
                        }
                        latencyTrace.end(
                            queueSpan,
                            details: "result=failure error=\(String(describing: type(of: error)))"
                        )
                        continuation.resume(throwing: error)
                    }
                }
            }
            latencyTrace.executorResumed(startResumeCheckpoint)
            guard microphoneCaptureEnabled.load(ordering: .acquiring),
                  captureGeneration.load(ordering: .acquiring) == generation,
                  activeRecordingID == recordingID else {
                throw CancellationError()
            }
            latencyTrace.event("recorder.audio_setup_queue.start_resumed", token: traceToken)
            logger.notice("startRecording: CoreAudioRecorder started successfully")

            startAudioMeterTimer()
            Task { [weak self] in
                guard let self, self.microphoneCaptureEnabled.load(ordering: .acquiring),
                      captureGeneration.load(ordering: .acquiring) == generation,
                      self.activeRecordingID == recordingID else { return }
                let span = latencyTrace.begin("recorder.pause_media", token: traceToken)
                await self.playbackController.pauseMedia()
                latencyTrace.end(span)
            }
        } catch {
            guard activeRecordingID == recordingID else { throw CancellationError() }
            logger.error("Failed to start recording: \(error.localizedDescription, privacy: .public)")
            await stopRecording(latencyTraceToken: traceToken)
            throw RecorderError.couldNotStartRecording
        }
    }

    func stopRecording(latencyTraceToken: VoiceInkLatencyTrace.Token? = nil) async {
        activeRecordingID = nil
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken ?? activeLatencyTraceToken
        latencyTrace.event("recorder.stop.enter", token: traceToken)
        logger.notice("stopRecording called")
        audioMuteTask?.cancel()
        audioMuteTask = nil
        audioMeterUpdateTimer?.cancel()
        audioMeterUpdateTimer = nil

        let currentRecorder = self.recorder
        let captureEnabled = microphoneCaptureEnabled
        latencyTrace.event("recorder.audio_setup_queue.schedule_stop", token: traceToken)
        // The hardware stop is already serialized and measured as sub-millisecond.
        // Finish inline so key-up does not pay a MainActor continuation-resume delay.
        audioSetupQueue.sync {
            let queueSpan = latencyTrace.begin("recorder.audio_setup_queue.stop", token: traceToken)
            if captureEnabled.load(ordering: .acquiring) {
                currentRecorder?.finishRecording(latencyTraceToken: traceToken)
            } else {
                currentRecorder?.stopRecording()
            }
            currentRecorder?.onAudioChunk = nil
            latencyTrace.end(queueSpan)
        }
        latencyTrace.event("recorder.audio_setup_queue.stop_completed", token: traceToken)
        onAudioChunk = nil

        smoothedValuesLock.lock()
        smoothedAverage = 0
        smoothedPeak = 0
        smoothedValuesLock.unlock()

        audioMeter = AudioMeter(averagePower: 0, peakPower: 0)

        let restorationCheckpoint = latencyTrace.executorEnqueued(
            "recorder.restore_audio.task",
            token: traceToken
        )
        audioRestorationTask = Task {
            latencyTrace.executorResumed(restorationCheckpoint)
            let span = latencyTrace.begin("recorder.restore_audio", token: traceToken)
            await mediaController.unmuteSystemAudio()
            await playbackController.resumeMedia()
            latencyTrace.end(span)
        }
        activeLatencyTraceToken = nil
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
