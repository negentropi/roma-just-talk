import AVFoundation
import CoreAudio
import Foundation
import VoiceInkCore
import XCTest
@testable import VoiceInk

#if DEBUG
@MainActor
final class RecorderMicrophonePrivacyTests: XCTestCase {
    private typealias CaptureStatus = (
        isRecording: Bool, isPreBuffering: Bool, hasAudioUnit: Bool,
        bufferedPCMBytes: Int, hasAudioChunkHandler: Bool
    )

    private var proofRequired: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["RJT_REQUIRE_MICROPHONE_PRIVACY_PROOF"] == "1"
            || environment["TEST_RUNNER_RJT_REQUIRE_MICROPHONE_PRIVACY_PROOF"] == "1"
    }

    func testQueuedPreRollCannotOpenMicrophoneAfterSuspension() async throws {
        try await withHardware(caseName: "queued_pre_roll") { recorder, _ in
            let release = await recorder.holdAudioSetupQueueForTesting()
            defer { release.signal() }
            let work = await self.queued(.preRoll, on: recorder) {
                await recorder.startPreRollBuffering()
            }
            let beforeTeardown = await self.queued(.status, on: recorder) {
                await recorder.microphoneCaptureStatus()
            }
            let suspension = await self.queued(.suspension, on: recorder) {
                await recorder.setMicrophoneCaptureEnabled(false)
            }
            release.signal()
            await work.value
            self.assertClosed(await beforeTeardown.value, caseName: "queued_pre_roll", phase: "before_teardown")
            await suspension.value
            self.assertClosed(await recorder.microphoneCaptureStatus(), caseName: "queued_pre_roll", phase: "suspended")
        }
    }

    func testQueuedRecordingCannotOpenMicrophoneAfterSuspension() async throws {
        try await withHardware(caseName: "queued_recording") { recorder, _ in
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("privacy-\(UUID().uuidString).wav")
            defer { try? FileManager.default.removeItem(at: output) }
            recorder.onAudioChunk = { _ in }
            let release = await recorder.holdAudioSetupQueueForTesting()
            defer { release.signal() }
            let work = await self.queued(.recording, on: recorder) {
                do {
                    try await recorder.startRecording(toOutputFile: output, latencyTraceToken: nil)
                    return true
                } catch {
                    return false
                }
            }
            let beforeTeardown = await self.queued(.status, on: recorder) {
                await recorder.microphoneCaptureStatus()
            }
            let suspension = await self.queued(.suspension, on: recorder) {
                await recorder.setMicrophoneCaptureEnabled(false)
            }
            release.signal()
            let started = await work.value
            XCTAssertFalse(started)
            self.assertClosed(await beforeTeardown.value, caseName: "queued_recording", phase: "before_teardown")
            await suspension.value
            self.assertClosed(await recorder.microphoneCaptureStatus(), caseName: "queued_recording", phase: "suspended")
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
    }

    func testQueuedDeviceSwitchCannotKeepMicrophoneOpenAfterSuspension() async throws {
        try await withHardware(caseName: "queued_switch_recovery") { recorder, _ in
            await recorder.startPreRollBuffering()
            let active = await self.waitForPCM(on: recorder)
            self.receipt("queued_switch_recovery", phase: "capturing_before_switch", status: active)
            XCTAssertTrue(active.hasAudioUnit && active.isPreBuffering && active.bufferedPCMBytes > 0)
            recorder.onAudioChunk = { _ in }
            let release = await recorder.holdAudioSetupQueueForTesting()
            defer { release.signal() }
            let work = await self.queued(.deviceSwitch, on: recorder) {
                await recorder.switchMicrophoneDeviceForTesting(to: AudioDeviceID.max)
            }
            let suspension = await self.queued(.suspension, on: recorder) {
                await recorder.setMicrophoneCaptureEnabled(false)
            }
            release.signal()
            await work.value
            await suspension.value
            self.assertClosed(await recorder.microphoneCaptureStatus(), caseName: "queued_switch_recovery", phase: "suspended")
        }
    }

    func testRapidReenableRejectsOldQueuedPreRollGeneration() async throws {
        try await withHardware(caseName: "off_on_generation") { recorder, _ in
            let release = await recorder.holdAudioSetupQueueForTesting()
            defer { release.signal() }
            let oldWork = await self.queued(.preRoll, on: recorder) {
                await recorder.startPreRollBuffering()
            }
            let beforeTeardown = await self.queued(.status, on: recorder) {
                await recorder.microphoneCaptureStatus()
            }
            let suspension = await self.queued(.suspension, on: recorder) {
                await recorder.setMicrophoneCaptureEnabled(false)
            }
            let reenable = await self.queued(.preRoll, on: recorder) {
                await recorder.setMicrophoneCaptureEnabled(true)
            }
            release.signal()
            await oldWork.value
            self.assertClosed(await beforeTeardown.value, caseName: "off_on_generation", phase: "old_generation_before_teardown")
            await suspension.value
            await reenable.value
            let restored = await self.waitForPCM(on: recorder)
            self.receipt("off_on_generation", phase: "new_generation_capturing", status: restored)
            XCTAssertTrue(restored.hasAudioUnit && restored.isPreBuffering && restored.bufferedPCMBytes > 0)
            await recorder.setMicrophoneCaptureEnabled(false)
            self.assertClosed(await recorder.microphoneCaptureStatus(), caseName: "off_on_generation", phase: "suspended_again")
        }
    }

    private func withHardware(
        caseName: String,
        operation: (Recorder, AudioDeviceID) async throws -> Void
    ) async throws {
        receipt(caseName, phase: "configuration")
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            try unavailable("Microphone TCC must be granted before privacy proof")
        }
        let manager = AudioDeviceManager.shared
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            manager.loadAvailableDevices { continuation.resume() }
        }
        guard let blackHole = manager.availableDevices.first(where: { $0.name == "BlackHole 2ch" }) else {
            try unavailable("BlackHole 2ch input is required for privacy proof")
        }
        let previousMode = manager.inputMode
        let previousDevice = manager.selectedDeviceID
        let previousRecording = manager.isRecordingActive
        let defaults = UserDefaults.standard
        let preferenceKeys = [VoiceInkLipDictationPreference.enabledKey, VoiceInkLipDictationPreference.lipOnlyKey]
        let previousPreferences = preferenceKeys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            manager.inputMode = previousMode
            manager.selectedDeviceID = previousDevice
            manager.isRecordingActive = previousRecording
            for (key, value) in previousPreferences {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        manager.inputMode = .custom
        manager.selectedDeviceID = blackHole.id
        manager.isRecordingActive = false
        defaults.set(false, forKey: VoiceInkLipDictationPreference.enabledKey)
        defaults.set(false, forKey: VoiceInkLipDictationPreference.lipOnlyKey)

        let probe = Recorder()
        await probe.startPreRollBuffering()
        let flowing = await waitForPCM(on: probe)
        receipt(caseName, phase: "hardware_precondition", status: flowing)
        await probe.setMicrophoneCaptureEnabled(false)
        guard flowing.hasAudioUnit, flowing.isPreBuffering, flowing.bufferedPCMBytes > 0 else {
            try unavailable("BlackHole AudioUnit did not produce actual PCM callbacks")
        }
        assertClosed(await probe.microphoneCaptureStatus(), caseName: caseName, phase: "precondition_teardown")

        let recorder = Recorder()
        do {
            try await operation(recorder, blackHole.id)
            await recorder.setMicrophoneCaptureEnabled(false)
        } catch {
            await recorder.setMicrophoneCaptureEnabled(false)
            throw error
        }
    }

    private func queued<Value: Sendable>(
        _ operation: Recorder.MicrophoneOperationForTesting,
        on recorder: Recorder,
        action: @escaping @MainActor () async -> Value
    ) async -> Task<Value, Never> {
        let enqueued = expectation(description: "Enqueued real microphone operation \(operation)")
        recorder.microphoneOperationEnqueuedForTesting = { if $0 == operation { enqueued.fulfill() } }
        let task = Task { @MainActor in await action() }
        await fulfillment(of: [enqueued], timeout: 5)
        recorder.microphoneOperationEnqueuedForTesting = nil
        return task
    }

    private func waitForPCM(on recorder: Recorder) async -> CaptureStatus {
        let deadline = Date().addingTimeInterval(5)
        var status = await recorder.microphoneCaptureStatus()
        while status.bufferedPCMBytes == 0, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
            status = await recorder.microphoneCaptureStatus()
        }
        return status
    }

    private func assertClosed(_ status: CaptureStatus, caseName: String, phase: String) {
        receipt(caseName, phase: phase, status: status)
        XCTAssertFalse(status.hasAudioUnit, "\(caseName)/\(phase) retained its actual AudioUnit")
        XCTAssertFalse(status.isRecording)
        XCTAssertFalse(status.isPreBuffering)
        XCTAssertEqual(status.bufferedPCMBytes, 0)
        XCTAssertFalse(status.hasAudioChunkHandler)
    }

    private func unavailable(_ reason: String) throws -> Never {
        if proofRequired {
            throw NSError(domain: "RecorderMicrophonePrivacyProof", code: 1, userInfo: [NSLocalizedDescriptionKey: reason])
        }
        throw XCTSkip(reason)
    }

    private func receipt(_ caseName: String, phase: String, status: CaptureStatus? = nil) {
        var fields: [String: Any] = [
            "event": "microphone_privacy_proof", "case": caseName,
            "phase": phase, "required": proofRequired
        ]
        if let status {
            fields["isRecording"] = status.isRecording
            fields["isPreBuffering"] = status.isPreBuffering
            fields["hasAudioUnit"] = status.hasAudioUnit
            fields["bufferedPCMBytes"] = status.bufferedPCMBytes
            fields["hasAudioChunkHandler"] = status.hasAudioChunkHandler
        }
        if let data = try? JSONSerialization.data(withJSONObject: fields, options: .sortedKeys) {
            print(String(decoding: data, as: UTF8.self))
        }
    }
}
#endif
