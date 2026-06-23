import Foundation
import IOKit.ps
import VoiceInkCore

extension VoiceInkRollingBufferPreloadSettings {
    static func perModelPreloadEnabled(
        for model: any TranscriptionModel,
        in defaults: UserDefaults = .standard
    ) -> Bool {
        perModelPreloadEnabled(forModelName: model.name, in: defaults)
    }
}

extension TranscriptionModel {
    var rollingBufferPreloadSnapshot: VoiceInkRollingBufferPreloadModelSnapshot {
        VoiceInkRollingBufferPreloadModelSnapshot(
            supportsStreaming: supportsStreaming,
            isCloudTranscriptionProvider: provider.transcriptionServiceRoute.isCloudTranscriptionProvider,
            supportsRecordedFileTranscription: supportsRecordedFileTranscription
        )
    }
}

protocol RollingBufferPowerStateProviding {
    func currentPowerState() -> VoiceInkRollingBufferPowerState
}

struct IOKitRollingBufferPowerStateProvider: RollingBufferPowerStateProviding {
    func currentPowerState() -> VoiceInkRollingBufferPowerState {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return VoiceInkRollingBufferPowerState(isOnBattery: false, batteryLevelPercent: nil)
        }

        var hasBattery = false
        var isOnBattery = false
        var levels: [Int] = []

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any] else {
                continue
            }

            let type = description[kIOPSTypeKey as String] as? String
            let currentCapacity = description[kIOPSCurrentCapacityKey as String] as? Int
            let maxCapacity = description[kIOPSMaxCapacityKey as String] as? Int
            let looksLikeBattery = type == (kIOPSInternalBatteryType as String) || currentCapacity != nil
            guard looksLikeBattery else { continue }

            hasBattery = true

            if description[kIOPSPowerSourceStateKey as String] as? String == (kIOPSBatteryPowerValue as String) {
                isOnBattery = true
            }

            if let currentCapacity, let maxCapacity, maxCapacity > 0 {
                levels.append(Int((Double(currentCapacity) / Double(maxCapacity) * 100).rounded()))
            }
        }

        return VoiceInkRollingBufferPowerState(
            isOnBattery: hasBattery && isOnBattery,
            batteryLevelPercent: levels.min()
        )
    }
}

final class RollingBufferPreloadRuntimeDiagnostics {
    static let shared = RollingBufferPreloadRuntimeDiagnostics()

    private let lock = NSLock()
    private var snapshot = VoiceInkRollingBufferQuickReleaseClaimSnapshot(
        strategy: .none,
        reason: nil,
        audioBytes: 0,
        updatedAt: nil,
        claimElapsedSeconds: nil,
        transcriptionReadySeconds: nil,
        activeWindowReadySeconds: nil,
        pasteStartingSeconds: nil,
        pasteCompletedSeconds: nil,
        pipelineReturnedSeconds: nil,
        idleSeconds: nil,
        sessionFinishedSeconds: nil,
        savedSeconds: nil
    )

    func recordQuickReleaseClaim(
        strategy: VoiceInkRollingBufferQuickReleaseClaimStrategy,
        reason: String? = nil,
        audioBytes: Int = 0,
        elapsedSeconds: TimeInterval? = nil,
        at updatedAt: Date = Date()
    ) {
        lock.lock()
        defer { lock.unlock() }
        snapshot = VoiceInkRollingBufferQuickReleaseClaimSnapshot(
            strategy: strategy,
            reason: reason,
            audioBytes: audioBytes,
            updatedAt: updatedAt,
            claimElapsedSeconds: elapsedSeconds,
            transcriptionReadySeconds: nil,
            activeWindowReadySeconds: nil,
            pasteStartingSeconds: nil,
            pasteCompletedSeconds: nil,
            pipelineReturnedSeconds: nil,
            idleSeconds: nil,
            sessionFinishedSeconds: nil,
            savedSeconds: nil
        )
    }

    func recordQuickReleaseTiming(
        stage: VoiceInkRollingBufferQuickReleaseTimingStage,
        elapsedSeconds: TimeInterval,
        at updatedAt: Date = Date()
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard snapshot.updatedAt != nil else { return }
        snapshot.recordTiming(stage: stage, elapsedSeconds: elapsedSeconds, at: updatedAt)
    }

    func currentQuickReleaseClaim() -> VoiceInkRollingBufferQuickReleaseClaimSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }
}
