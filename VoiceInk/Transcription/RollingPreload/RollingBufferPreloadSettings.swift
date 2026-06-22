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
            isCloudTranscriptionProvider: provider.transcriptionServiceRoute.isCloudTranscriptionProvider
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

enum RollingBufferBufferedSnapshotTranscriptionStrategy {
    case recordedFile
    case unavailable
}

enum RollingBufferBufferedSnapshotTranscriptionPolicy {
    static func strategy(for model: any TranscriptionModel) -> RollingBufferBufferedSnapshotTranscriptionStrategy {
        model.supportsRecordedFileTranscription ? .recordedFile : .unavailable
    }
}

enum RollingBufferQuickReleaseClaimStrategy: String {
    case none
    case readyPreload
    case bufferedAudioSnapshot
    case unavailable
    case invalidated
    case failed

    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .readyPreload:
            return "Ready Preload"
        case .bufferedAudioSnapshot:
            return "Buffered Audio Snapshot"
        case .unavailable:
            return "Unavailable"
        case .invalidated:
            return "Invalidated"
        case .failed:
            return "Failed"
        }
    }
}

enum RollingBufferQuickReleaseTimingStage {
    case transcriptionReady
    case activeWindowReady
    case pasteStarting
    case pasteCompleted
    case pipelineReturned
    case idle
    case sessionFinished
    case saved
}

struct RollingBufferQuickReleaseClaimSnapshot: Equatable {
    let strategy: RollingBufferQuickReleaseClaimStrategy
    let reason: String?
    let audioBytes: Int
    var updatedAt: Date?
    var claimElapsedSeconds: TimeInterval?
    var transcriptionReadySeconds: TimeInterval?
    var activeWindowReadySeconds: TimeInterval?
    var pasteStartingSeconds: TimeInterval?
    var pasteCompletedSeconds: TimeInterval?
    var pipelineReturnedSeconds: TimeInterval?
    var idleSeconds: TimeInterval?
    var sessionFinishedSeconds: TimeInterval?
    var savedSeconds: TimeInterval?

    var displaySummary: String {
        guard updatedAt != nil else { return "None" }

        var parts = [strategy.displayName]
        if let reason, !reason.isEmpty {
            parts.append(reason)
        }
        if audioBytes > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(audioBytes), countStyle: .file))
        }
        if let pasteCompletedSeconds {
            parts.append("paste \(Self.formatSeconds(pasteCompletedSeconds))")
        } else if let pasteStartingSeconds {
            parts.append("paste-start \(Self.formatSeconds(pasteStartingSeconds))")
        } else if let activeWindowReadySeconds {
            parts.append("window \(Self.formatSeconds(activeWindowReadySeconds))")
        } else if let transcriptionReadySeconds {
            parts.append("transcribed \(Self.formatSeconds(transcriptionReadySeconds))")
        } else if let claimElapsedSeconds {
            parts.append("claim \(Self.formatSeconds(claimElapsedSeconds))")
        }
        if let idleSeconds {
            parts.append("idle \(Self.formatSeconds(idleSeconds))")
        } else if let pipelineReturnedSeconds {
            parts.append("returned \(Self.formatSeconds(pipelineReturnedSeconds))")
        }
        return parts.joined(separator: " - ")
    }

    var exportSummary: String {
        guard let updatedAt else { return displaySummary }
        let timingParts = [
            Self.timingPart("claim", claimElapsedSeconds),
            Self.timingPart("transcription", transcriptionReadySeconds),
            Self.timingPart("active-window", activeWindowReadySeconds),
            Self.timingPart("paste-start", pasteStartingSeconds),
            Self.timingPart("paste-complete", pasteCompletedSeconds),
            Self.timingPart("returned", pipelineReturnedSeconds),
            Self.timingPart("idle", idleSeconds),
            Self.timingPart("session-finished", sessionFinishedSeconds),
            Self.timingPart("saved", savedSeconds)
        ].compactMap { $0 }
        let timingSummary = timingParts.isEmpty ? "" : " | \(timingParts.joined(separator: ", "))"
        return "\(displaySummary) at \(updatedAt.formatted(date: .numeric, time: .standard))\(timingSummary)"
    }

    mutating func recordTiming(stage: RollingBufferQuickReleaseTimingStage, elapsedSeconds: TimeInterval, at date: Date) {
        updatedAt = date
        switch stage {
        case .transcriptionReady:
            transcriptionReadySeconds = elapsedSeconds
        case .activeWindowReady:
            activeWindowReadySeconds = elapsedSeconds
        case .pasteStarting:
            pasteStartingSeconds = elapsedSeconds
        case .pasteCompleted:
            pasteCompletedSeconds = elapsedSeconds
        case .pipelineReturned:
            pipelineReturnedSeconds = elapsedSeconds
        case .idle:
            idleSeconds = elapsedSeconds
        case .sessionFinished:
            sessionFinishedSeconds = elapsedSeconds
        case .saved:
            savedSeconds = elapsedSeconds
        }
    }

    private static func timingPart(_ label: String, _ seconds: TimeInterval?) -> String? {
        guard let seconds else { return nil }
        return "\(label)=\(formatSeconds(seconds))"
    }

    private static func formatSeconds(_ seconds: TimeInterval) -> String {
        String(format: "%.3fs", seconds)
    }
}

final class RollingBufferPreloadRuntimeDiagnostics {
    static let shared = RollingBufferPreloadRuntimeDiagnostics()

    private let lock = NSLock()
    private var snapshot = RollingBufferQuickReleaseClaimSnapshot(
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
        strategy: RollingBufferQuickReleaseClaimStrategy,
        reason: String? = nil,
        audioBytes: Int = 0,
        elapsedSeconds: TimeInterval? = nil,
        at updatedAt: Date = Date()
    ) {
        lock.lock()
        defer { lock.unlock() }
        snapshot = RollingBufferQuickReleaseClaimSnapshot(
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
        stage: RollingBufferQuickReleaseTimingStage,
        elapsedSeconds: TimeInterval,
        at updatedAt: Date = Date()
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard snapshot.updatedAt != nil else { return }
        snapshot.recordTiming(stage: stage, elapsedSeconds: elapsedSeconds, at: updatedAt)
    }

    func currentQuickReleaseClaim() -> RollingBufferQuickReleaseClaimSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }
}
