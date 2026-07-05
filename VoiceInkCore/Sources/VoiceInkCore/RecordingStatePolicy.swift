import Foundation

public enum VoiceInkRecordingState: Equatable, Sendable {
    case idle
    case starting
    case recording
    case transcribing
    case enhancing
    case busy
}

public enum VoiceInkAudioMeterLevel {
    public static let defaultMinimumDecibels: Float = -60
    public static let defaultMaximumDecibels: Float = 0
    public static let defaultPreviousLevelWeight: Float = 0.6
    public static let defaultLevelHistoryLimit = 40
    public static let macOSUpdateIntervalMilliseconds = 17
    public static let iOSUpdateInterval: TimeInterval = 0.1
    public static let macOSVisualizerAnimationMinimumInterval: TimeInterval = 0.016
    public static let macOSVisualizerBarCount = 15
    public static let macOSVisualizerBarWidth: Double = 3
    public static let macOSVisualizerBarSpacing: Double = 2
    public static let macOSVisualizerMinimumBarHeight: Double = 4
    public static let macOSVisualizerMaximumBarHeight: Double = 28
    public static let macOSVisualizerPhaseStep: Double = 0.4
    public static let macOSVisualizerWaveFrequency: Double = 8
    public static let macOSVisualizerAmplitudeExponent: Double = 0.7
    public static let macOSVisualizerCenterBoostDropoff: Double = 0.4
    public static let iOSVisualizerBarCount = 8
    public static let iOSVisualizerBarSpacing: Double = 3
    public static let iOSVisualizerBarMinimumWidth: Double = 2
    public static let iOSVisualizerHorizontalPadding: Double = 2
    public static let iOSVisualizerWidthInset: Double = 16
    public static let iOSVisualizerFrameHeight: Double = 48
    public static let iOSVisualizerMinimumBarHeight: Double = 4
    public static let iOSVisualizerAnimationDuration: TimeInterval = 0.12
    public static let visualizerAccessibilityLabel = "Audio level visualizer"

    public static func normalizedLevel(
        forDecibels decibels: Float,
        minimumDecibels: Float = defaultMinimumDecibels,
        maximumDecibels: Float = defaultMaximumDecibels
    ) -> Float {
        guard maximumDecibels > minimumDecibels else {
            return decibels >= maximumDecibels ? 1 : 0
        }

        if decibels < minimumDecibels {
            return 0
        }

        if decibels >= maximumDecibels {
            return 1
        }

        return (decibels - minimumDecibels) / (maximumDecibels - minimumDecibels)
    }

    public static func smoothedLevel(
        previous: Float,
        current: Float,
        previousWeight: Float = defaultPreviousLevelWeight
    ) -> Float {
        let clampedPreviousWeight = min(max(previousWeight, 0), 1)
        return previous * clampedPreviousWeight + current * (1 - clampedPreviousWeight)
    }

    public static func boundedHistory(
        appending level: Float,
        to history: [Float],
        limit: Int = defaultLevelHistoryLimit
    ) -> [Float] {
        guard limit > 0 else {
            return []
        }

        let updatedHistory = history + [level]
        guard updatedHistory.count > limit else {
            return updatedHistory
        }

        return Array(updatedHistory.suffix(limit))
    }

    public static func macOSMeterUpdatePlan(
        averageDecibels: Float,
        peakDecibels: Float,
        previousSmoothedAverage: Float,
        previousSmoothedPeak: Float
    ) -> VoiceInkMacOSAudioMeterUpdatePlan {
        let normalizedAverage = normalizedLevel(forDecibels: averageDecibels)
        let normalizedPeak = normalizedLevel(forDecibels: peakDecibels)

        return VoiceInkMacOSAudioMeterUpdatePlan(
            smoothedAverage: smoothedLevel(previous: previousSmoothedAverage, current: normalizedAverage),
            smoothedPeak: smoothedLevel(previous: previousSmoothedPeak, current: normalizedPeak)
        )
    }

    public static func iOSMeterHistoryUpdatePlan(
        averageDecibels: Float,
        previousHistory: [Float]
    ) -> VoiceInkIOSAudioMeterHistoryUpdatePlan {
        let visibleLevel = normalizedLevel(forDecibels: averageDecibels)
        return VoiceInkIOSAudioMeterHistoryUpdatePlan(
            normalizedLevel: visibleLevel,
            levelsHistory: boundedHistory(appending: visibleLevel, to: previousHistory)
        )
    }

    public static func visualizerLevel(
        forBarAt index: Int,
        levels: [Float],
        barCount: Int = iOSVisualizerBarCount
    ) -> Float {
        guard index >= 0, !levels.isEmpty, barCount > 0 else {
            return 0
        }

        let span = max(1, min(levels.count, barCount))
        let step = max(1, levels.count / span)
        let sourceIndex = max(0, levels.count - 1 - index * step)
        let sourceLevel = levels[sourceIndex]
        return max(0, min(1, sourceLevel))
    }

    public static func iOSVisualizerBarWidth(
        containerWidth: Double,
        barCount: Int = iOSVisualizerBarCount,
        spacing: Double = iOSVisualizerBarSpacing,
        widthInset: Double = iOSVisualizerWidthInset,
        minimumWidth: Double = iOSVisualizerBarMinimumWidth
    ) -> Double {
        guard barCount > 0 else { return minimumWidth }
        return max(minimumWidth, (containerWidth - widthInset) / Double(barCount) - spacing)
    }

    public static func iOSVisualizerBarHeight(
        forBarAt index: Int,
        levels: [Float],
        containerHeight: Double,
        barCount: Int = iOSVisualizerBarCount,
        minimumHeight: Double = iOSVisualizerMinimumBarHeight
    ) -> Double {
        let level = Double(visualizerLevel(forBarAt: index, levels: levels, barCount: barCount))
        return minimumHeight + (containerHeight - minimumHeight) * level
    }

    public static func macOSVisualizerBarHeight(
        forBarAt index: Int,
        time: TimeInterval,
        averagePower: Double,
        isActive: Bool,
        barCount: Int = macOSVisualizerBarCount,
        minimumHeight: Double = macOSVisualizerMinimumBarHeight,
        maximumHeight: Double = macOSVisualizerMaximumBarHeight
    ) -> Double {
        guard isActive, index >= 0, index < barCount, barCount > 1, maximumHeight > minimumHeight else {
            return minimumHeight
        }

        let amplitude = max(0, min(1, pow(averagePower, macOSVisualizerAmplitudeExponent)))
        let phase = Double(index) * macOSVisualizerPhaseStep
        let wave = sin(time * macOSVisualizerWaveFrequency + phase) * 0.5 + 0.5
        let centerDistance = abs(Double(index) - Double(barCount) / 2) / Double(barCount / 2)
        let centerBoost = 1.0 - centerDistance * macOSVisualizerCenterBoostDropoff

        return max(minimumHeight, minimumHeight + amplitude * wave * centerBoost * (maximumHeight - minimumHeight))
    }
}

public struct VoiceInkMacOSAudioMeterUpdatePlan: Equatable, Sendable {
    public let smoothedAverage: Float
    public let smoothedPeak: Float

    public init(smoothedAverage: Float, smoothedPeak: Float) {
        self.smoothedAverage = smoothedAverage
        self.smoothedPeak = smoothedPeak
    }
}

public struct VoiceInkIOSAudioMeterHistoryUpdatePlan: Equatable, Sendable {
    public let normalizedLevel: Float
    public let levelsHistory: [Float]

    public init(normalizedLevel: Float, levelsHistory: [Float]) {
        self.normalizedLevel = normalizedLevel
        self.levelsHistory = levelsHistory
    }
}

fileprivate enum VoiceInkRecorderUIToggleAction: Equatable, Sendable {
    case toggleRecord
    case cancelRecording
    case dismissRecorder
}

public enum VoiceInkRecordingPermissionStatus: Equatable, Sendable {
    case granted
    case denied
    case undetermined
}

enum VoiceInkRecordingPermissionAction: Equatable, Sendable {
    case startRecording
    case requestPermission
    case presentPermissionDenied

    func applyRuntimeState(
        startRecording: @escaping () -> Void,
        presentPermissionDenied: @escaping () -> Void,
        requestPermission: @escaping (@escaping (Bool) -> Void) -> Void
    ) {
        switch self {
        case .startRecording:
            startRecording()
        case .presentPermissionDenied:
            presentPermissionDenied()
        case .requestPermission:
            requestPermission { granted in
                VoiceInkRecordingPermissionPolicy.plan(afterPermissionRequestGranted: granted)
                    .applyRuntimeState(
                        startRecording: startRecording,
                        presentPermissionDenied: presentPermissionDenied,
                        requestPermission: requestPermission
                    )
            }
        }
    }
}

public struct VoiceInkRecordingPermissionPlan: Sendable {
    private let action: VoiceInkRecordingPermissionAction

    init(action: VoiceInkRecordingPermissionAction) {
        self.action = action
    }

    public func applyRuntimeState(
        startRecording: @escaping () -> Void,
        presentPermissionDenied: @escaping () -> Void,
        requestPermission: @escaping (@escaping (Bool) -> Void) -> Void
    ) {
        action.applyRuntimeState(
            startRecording: startRecording,
            presentPermissionDenied: presentPermissionDenied,
            requestPermission: requestPermission
        )
    }
}

enum VoiceInkRecordingPermissionSettingsAction: Equatable, Sendable {
    case openSettings(URL)
    case ignore

    func applyRuntimeState(openSettings: (URL) -> Void) {
        switch self {
        case .openSettings(let url):
            openSettings(url)
        case .ignore:
            return
        }
    }
}

public struct VoiceInkRecordingPermissionSettingsPlan: Sendable {
    private let action: VoiceInkRecordingPermissionSettingsAction

    init(action: VoiceInkRecordingPermissionSettingsAction) {
        self.action = action
    }

    public func applyRuntimeState(openSettings: (URL) -> Void) {
        action.applyRuntimeState(openSettings: openSettings)
    }
}

public enum VoiceInkRecordingPermissionPolicy {
    public static func plan(for status: VoiceInkRecordingPermissionStatus) -> VoiceInkRecordingPermissionPlan {
        switch status {
        case .granted:
            return VoiceInkRecordingPermissionPlan(action: .startRecording)
        case .denied:
            return VoiceInkRecordingPermissionPlan(action: .presentPermissionDenied)
        case .undetermined:
            return VoiceInkRecordingPermissionPlan(action: .requestPermission)
        }
    }

    public static func plan(afterPermissionRequestGranted isGranted: Bool) -> VoiceInkRecordingPermissionPlan {
        VoiceInkRecordingPermissionPlan(
            action: isGranted ? .startRecording : .presentPermissionDenied
        )
    }

    public static func settingsOpenPlan(
        settingsURL: URL?,
        canOpenURL: (URL) -> Bool
    ) -> VoiceInkRecordingPermissionSettingsPlan {
        guard let settingsURL, canOpenURL(settingsURL) else {
            return VoiceInkRecordingPermissionSettingsPlan(action: .ignore)
        }

        return VoiceInkRecordingPermissionSettingsPlan(
            action: .openSettings(settingsURL)
        )
    }
}

public struct VoiceInkRecorderProcessingPresentation: Equatable, Sendable {
    public let label: String
    public let progressAnimationInterval: TimeInterval

    public init(
        label: String,
        progressAnimationInterval: TimeInterval
    ) {
        self.label = label
        self.progressAnimationInterval = progressAnimationInterval
    }
}

public struct VoiceInkRecordingFlowState: Equatable, Sendable {
    public static let durationUpdateInterval: TimeInterval = 0.1

    public private(set) var recordingState: VoiceInkRecordingState
    public private(set) var animate: Bool
    public private(set) var isRecordingSheetPresented: Bool
    public private(set) var currentDuration: TimeInterval

    public init(
        recordingState: VoiceInkRecordingState = .idle,
        animate: Bool = false,
        isRecordingSheetPresented: Bool = false,
        currentDuration: TimeInterval = 0
    ) {
        self.recordingState = recordingState
        self.animate = animate
        self.isRecordingSheetPresented = isRecordingSheetPresented
        self.currentDuration = currentDuration
    }

    public mutating func prepareRecordingStart() {
        recordingState = .recording
        animate = true
    }

    public mutating func completeRecordingStart() {
        currentDuration = 0
        isRecordingSheetPresented = true
    }

    public mutating func failRecordingStart() {
        recordingState = .idle
        animate = false
        isRecordingSheetPresented = false
    }

    public mutating func finishRecording() {
        recordingState = .idle
        animate = false
        isRecordingSheetPresented = false
    }

    public mutating func cancelRecording() {
        finishRecording()
        currentDuration = 0
    }

    public mutating func setRecordingSheetPresented(_ isPresented: Bool) {
        isRecordingSheetPresented = isPresented
    }

    public mutating func advanceDuration(by interval: TimeInterval = durationUpdateInterval) {
        currentDuration += interval
    }

    public func stopRecordingPlan(audioFileURL: String?) -> VoiceInkRecordingStopPlan {
        var flowStateAfterStop = self
        flowStateAfterStop.finishRecording()

        return VoiceInkRecordingStopPlan(
            flowStateAfterStop: flowStateAfterStop,
            pendingDraft: audioFileURL.map {
                VoiceInkRecordingTranscriptionDraft.pending(
                    duration: currentDuration,
                    audioFileURL: $0
                )
            }
        )
    }

    public func cancelRecordingPlan() -> VoiceInkRecordingCancelPlan {
        var flowStateAfterCancel = self
        flowStateAfterCancel.cancelRecording()
        return VoiceInkRecordingCancelPlan(flowStateAfterCancel: flowStateAfterCancel)
    }
}

public struct VoiceInkRecordingStopPlan: Equatable, Sendable {
    public let flowStateAfterStop: VoiceInkRecordingFlowState
    public let pendingDraft: VoiceInkRecordingTranscriptionDraft?

    public init(
        flowStateAfterStop: VoiceInkRecordingFlowState,
        pendingDraft: VoiceInkRecordingTranscriptionDraft?
    ) {
        self.flowStateAfterStop = flowStateAfterStop
        self.pendingDraft = pendingDraft
    }

    public func applyRuntimeState(
        stopRecorder: () -> Void,
        stopDurationTimer: () -> Void,
        setFlowState: (VoiceInkRecordingFlowState) -> Void,
        updateRecordingState: (Bool) -> Void,
        insertPendingDraft: (VoiceInkRecordingTranscriptionDraft) -> Void
    ) {
        stopRecorder()
        stopDurationTimer()
        setFlowState(flowStateAfterStop)
        updateRecordingState(false)

        if let pendingDraft {
            insertPendingDraft(pendingDraft)
        }
    }
}

public struct VoiceInkRecordingCancelPlan: Equatable, Sendable {
    public let flowStateAfterCancel: VoiceInkRecordingFlowState

    public init(flowStateAfterCancel: VoiceInkRecordingFlowState) {
        self.flowStateAfterCancel = flowStateAfterCancel
    }

    public func applyRuntimeState(
        discardRecorder: () -> Void,
        stopDurationTimer: () -> Void,
        setFlowState: (VoiceInkRecordingFlowState) -> Void,
        updateRecordingState: (Bool) -> Void
    ) {
        discardRecorder()
        stopDurationTimer()
        setFlowState(flowStateAfterCancel)
        updateRecordingState(false)
    }
}

public enum VoiceInkAudioRecorderStopMode: Equatable, Sendable {
    case keepRecordingFile
    case discardRecordingFile
}

public struct VoiceInkAudioRecorderStopPlan: Equatable, Sendable {
    private let shouldStopRecorder: Bool
    private let shouldInvalidateMeterTimer: Bool
    private let isRecordingAfterStop: Bool
    private let shouldClearAudioLevels: Bool
    private let shouldDeleteCurrentRecordingFile: Bool
    private let shouldClearCurrentRecordingURL: Bool
    private let shouldScheduleSessionDeactivation: Bool

    fileprivate init(
        shouldStopRecorder: Bool,
        shouldInvalidateMeterTimer: Bool,
        isRecordingAfterStop: Bool,
        shouldClearAudioLevels: Bool,
        shouldDeleteCurrentRecordingFile: Bool,
        shouldClearCurrentRecordingURL: Bool,
        shouldScheduleSessionDeactivation: Bool
    ) {
        self.shouldStopRecorder = shouldStopRecorder
        self.shouldInvalidateMeterTimer = shouldInvalidateMeterTimer
        self.isRecordingAfterStop = isRecordingAfterStop
        self.shouldClearAudioLevels = shouldClearAudioLevels
        self.shouldDeleteCurrentRecordingFile = shouldDeleteCurrentRecordingFile
        self.shouldClearCurrentRecordingURL = shouldClearCurrentRecordingURL
        self.shouldScheduleSessionDeactivation = shouldScheduleSessionDeactivation
    }

    public func applyRuntimeState(
        stopRecorder: () -> Void,
        invalidateMeterTimer: () -> Void,
        setIsRecording: (Bool) -> Void,
        clearAudioLevels: () -> Void,
        deleteCurrentRecordingFile: () -> Void,
        clearCurrentRecordingURL: () -> Void,
        scheduleSessionDeactivation: () -> Void
    ) {
        if shouldStopRecorder {
            stopRecorder()
        }
        if shouldInvalidateMeterTimer {
            invalidateMeterTimer()
        }
        setIsRecording(isRecordingAfterStop)
        if shouldClearAudioLevels {
            clearAudioLevels()
        }
        if shouldDeleteCurrentRecordingFile {
            deleteCurrentRecordingFile()
        }
        if shouldClearCurrentRecordingURL {
            clearCurrentRecordingURL()
        }
        if shouldScheduleSessionDeactivation {
            scheduleSessionDeactivation()
        }
    }
}

public enum VoiceInkAudioRecorderStopPolicy {
    public static func plan(for mode: VoiceInkAudioRecorderStopMode) -> VoiceInkAudioRecorderStopPlan {
        VoiceInkAudioRecorderStopPlan(
            shouldStopRecorder: true,
            shouldInvalidateMeterTimer: true,
            isRecordingAfterStop: false,
            shouldClearAudioLevels: true,
            shouldDeleteCurrentRecordingFile: mode == .discardRecordingFile,
            shouldClearCurrentRecordingURL: mode == .discardRecordingFile,
            shouldScheduleSessionDeactivation: true
        )
    }
}

public enum VoiceInkAudioRecorderStartFailurePolicy {
    public static let returnedFalseErrorCode = 1001
    public static let errorDomainComponent = "AudioRecorder"
    public static let returnedFalseDescription = "Failed to start AVAudioRecorder. The record() method returned false. This often happens in the background if the audio session is not configured correctly or if there is a conflict with another app."

    public static var returnedFalseErrorDomain: String {
        VoiceInkAppIdentity.errorDomain(component: errorDomainComponent)
    }

    public static var returnedFalseUserInfo: [String: String] {
        [NSLocalizedDescriptionKey: returnedFalseDescription]
    }

    public static func returnedFalseError() -> NSError {
        NSError(
            domain: returnedFalseErrorDomain,
            code: returnedFalseErrorCode,
            userInfo: returnedFalseUserInfo
        )
    }
}

public enum VoiceInkMacOSCoreAudioRecorderDiagnostics {
    public static let assumedLatencySampleRate: Double = 48_000
    public static let unknownValueText = "Unknown"

    public enum TransportKind: Equatable, Sendable {
        case builtIn
        case usb
        case bluetooth
        case bluetoothLE
        case aggregate
        case virtual
        case pci
        case fireWire
        case displayPort
        case hdmi
        case avb
        case thunderbolt
        case other(UInt32)
        case unknown
    }

    public static func knownText(_ text: String?) -> String {
        text ?? unknownValueText
    }

    public static func transportText(_ transportKind: TransportKind) -> String {
        switch transportKind {
        case .builtIn:
            return "Built-in"
        case .usb:
            return "USB"
        case .bluetooth:
            return "Bluetooth"
        case .bluetoothLE:
            return "Bluetooth LE"
        case .aggregate:
            return "Aggregate"
        case .virtual:
            return "Virtual"
        case .pci:
            return "PCI"
        case .fireWire:
            return "FireWire"
        case .displayPort:
            return "DisplayPort"
        case .hdmi:
            return "HDMI"
        case .avb:
            return "AVB"
        case .thunderbolt:
            return "Thunderbolt"
        case .other(let rawValue):
            return "Other (\(rawValue))"
        case .unknown:
            return unknownValueText
        }
    }

    public static func deviceInfoMessage(name: String, uid: String) -> String {
        "🎙️ Device info: name=\(name), uid=\(uid)"
    }

    public static func deviceDetailsMessage(transport: String, manufacturer: String) -> String {
        "🎙️ Device details: transport=\(transport), manufacturer=\(manufacturer)"
    }

    public static func bufferLatencyMilliseconds(bufferFrameSize: UInt32) -> Double {
        (Double(bufferFrameSize) / assumedLatencySampleRate) * 1_000
    }

    public static func bufferLatencyMessage(bufferFrameSize: UInt32) -> String {
        let latencyMilliseconds = bufferLatencyMilliseconds(bufferFrameSize: bufferFrameSize)
        return "🎙️ Buffer size: \(bufferFrameSize) frames, ~latency: \(String(format: "%.1f", latencyMilliseconds))ms"
    }
}

public struct VoiceInkAppGroupRecordingState: Equatable, Sendable {
    public let isRecording: Bool
    public let shouldClearStaleState: Bool

    public init(isRecording: Bool, shouldClearStaleState: Bool) {
        self.isRecording = isRecording
        self.shouldClearStaleState = shouldClearStaleState
    }
}

public struct VoiceInkAppGroupRecordingStateWritePlan: Equatable, Sendable {
    private let isRecording: Bool?
    private let lastRecordingTimestamp: TimeInterval

    init(isRecording: Bool?, lastRecordingTimestamp: TimeInterval) {
        self.isRecording = isRecording
        self.lastRecordingTimestamp = lastRecordingTimestamp
    }

    public func applyRuntimeState(
        setIsRecording: (Bool) -> Void,
        setLastRecordingTimestamp: (TimeInterval) -> Void
    ) {
        if let isRecording {
            setIsRecording(isRecording)
        }

        setLastRecordingTimestamp(lastRecordingTimestamp)
    }
}

public struct VoiceInkAppGroupRecordingStateMutationPlan: Equatable, Sendable {
    private let writePlan: VoiceInkAppGroupRecordingStateWritePlan
    private let darwinNotificationName: String

    init(
        writePlan: VoiceInkAppGroupRecordingStateWritePlan,
        darwinNotificationName: String
    ) {
        self.writePlan = writePlan
        self.darwinNotificationName = darwinNotificationName
    }

    public func applyRuntimeState(
        applyWritePlan: (VoiceInkAppGroupRecordingStateWritePlan) -> Void,
        postDarwinNotification: (String) -> Void
    ) {
        applyWritePlan(writePlan)
        postDarwinNotification(darwinNotificationName)
    }
}

public struct VoiceInkAppGroupRecordingStateReadPlan: Equatable, Sendable {
    private let state: VoiceInkAppGroupRecordingState
    private let staleStateRepairMutationPlan: VoiceInkAppGroupRecordingStateMutationPlan?

    init(
        state: VoiceInkAppGroupRecordingState,
        staleStateRepairMutationPlan: VoiceInkAppGroupRecordingStateMutationPlan?
    ) {
        self.state = state
        self.staleStateRepairMutationPlan = staleStateRepairMutationPlan
    }

    public func applyRuntimeState(
        repairStaleState: (VoiceInkAppGroupRecordingStateMutationPlan) -> Void
    ) -> VoiceInkAppGroupRecordingState {
        if let staleStateRepairMutationPlan {
            repairStaleState(staleStateRepairMutationPlan)
        }

        return state
    }
}

public enum VoiceInkAppGroupRecordingStatePolicy {
    public static let staleRecordingInterval: TimeInterval = 30

    public enum UserDefaultsKey {
        public static let isRecording = "isRecording"
        public static let lastRecordingTimestamp = "lastRecordingTimestamp"
    }

    public static func stopRequestedWritePlan(
        now: Date = Date()
    ) -> VoiceInkAppGroupRecordingStateWritePlan {
        VoiceInkAppGroupRecordingStateWritePlan(
            isRecording: nil,
            lastRecordingTimestamp: now.timeIntervalSince1970
        )
    }

    public static func stopRequestedMutationPlan(
        now: Date = Date()
    ) -> VoiceInkAppGroupRecordingStateMutationPlan {
        VoiceInkAppGroupRecordingStateMutationPlan(
            writePlan: stopRequestedWritePlan(now: now),
            darwinNotificationName: VoiceInkAppIdentity.iOSStopRecordingDarwinNotificationName
        )
    }

    public static func recordingStateWritePlan(
        isRecording: Bool,
        now: Date = Date()
    ) -> VoiceInkAppGroupRecordingStateWritePlan {
        VoiceInkAppGroupRecordingStateWritePlan(
            isRecording: isRecording,
            lastRecordingTimestamp: now.timeIntervalSince1970
        )
    }

    public static func recordingStateMutationPlan(
        isRecording: Bool,
        now: Date = Date()
    ) -> VoiceInkAppGroupRecordingStateMutationPlan {
        VoiceInkAppGroupRecordingStateMutationPlan(
            writePlan: recordingStateWritePlan(isRecording: isRecording, now: now),
            darwinNotificationName: VoiceInkAppIdentity.iOSRecordingStateChangedDarwinNotificationName
        )
    }

    public static func state(
        storedIsRecording: Bool,
        lastRecordingTimestamp: TimeInterval,
        now: Date = Date()
    ) -> VoiceInkAppGroupRecordingState {
        guard storedIsRecording else {
            return VoiceInkAppGroupRecordingState(
                isRecording: false,
                shouldClearStaleState: false
            )
        }

        let isStale = now.timeIntervalSince1970 - lastRecordingTimestamp > staleRecordingInterval
        return VoiceInkAppGroupRecordingState(
            isRecording: !isStale,
            shouldClearStaleState: isStale
        )
    }

    public static func readPlan(
        storedIsRecording: Bool,
        lastRecordingTimestamp: TimeInterval,
        now: Date = Date()
    ) -> VoiceInkAppGroupRecordingStateReadPlan {
        let currentState = state(
            storedIsRecording: storedIsRecording,
            lastRecordingTimestamp: lastRecordingTimestamp,
            now: now
        )
        let repairMutationPlan: VoiceInkAppGroupRecordingStateMutationPlan?
        if currentState.shouldClearStaleState {
            repairMutationPlan = recordingStateMutationPlan(isRecording: false, now: now)
        } else {
            repairMutationPlan = nil
        }

        return VoiceInkAppGroupRecordingStateReadPlan(
            state: currentState,
            staleStateRepairMutationPlan: repairMutationPlan
        )
    }
}

public enum VoiceInkAppGroupRecordingDiagnostics {
    public static let staleRecordingStateClearedMessage = "Recording state appears stale, clearing it"

    public static func updatedRecordingStateMessage(isRecording: Bool) -> String {
        "Updated recording state: \(isRecording)"
    }
}

public enum VoiceInkIOSRecordingCoordinationDiagnostics {
    public static let clearedStaleRecordingStateOnLaunchMessage = "Cleared stale recording state on app launch"
    public static let recordDeepLinkOpenedMessage = "URL scheme triggered: open app for recording"
    public static let keyboardRecordingRequestOpenedMessage = "App opened via keyboard extension - recording requested"
    public static let recordingManagerInitializedMessage = "RecordingManager initialized"
    public static let keyboardStopRecordingRequestedMessage = "Stop recording requested from keyboard extension"
}

public enum VoiceInkKeyboardRecordingTiming {
    public static let appLaunchRecordingStartDelay: TimeInterval = 0.5
    public static let recordingStatusPollingInterval: TimeInterval = 0.5
    public static let openAppFallbackResetDelay: TimeInterval = 2.0
}

enum VoiceInkLaunchRecordingRequestAction: Equatable, Sendable {
    case none
    case deferUntilOnboardingCompletes
    case startRecordingAfterLaunchDelay

    func applyRuntimeState(startRecordingAfterLaunchDelay: () -> Void) {
        switch self {
        case .none, .deferUntilOnboardingCompletes:
            return
        case .startRecordingAfterLaunchDelay:
            startRecordingAfterLaunchDelay()
        }
    }
}

public struct VoiceInkLaunchRecordingRequestPlan: Sendable {
    private let action: VoiceInkLaunchRecordingRequestAction

    init(action: VoiceInkLaunchRecordingRequestAction) {
        self.action = action
    }

    public func applyRuntimeState(startRecordingAfterLaunchDelay: () -> Void) {
        action.applyRuntimeState(startRecordingAfterLaunchDelay: startRecordingAfterLaunchDelay)
    }
}

public struct VoiceInkLaunchRecordingRequestState: Equatable, Sendable {
    public private(set) var hasPendingRecordingAfterOnboarding: Bool

    public init(hasPendingRecordingAfterOnboarding: Bool = false) {
        self.hasPendingRecordingAfterOnboarding = hasPendingRecordingAfterOnboarding
    }

    public mutating func requestRecording(
        hasCompletedOnboarding: Bool
    ) -> VoiceInkLaunchRecordingRequestPlan {
        guard hasCompletedOnboarding else {
            hasPendingRecordingAfterOnboarding = true
            return VoiceInkLaunchRecordingRequestPlan(action: .deferUntilOnboardingCompletes)
        }

        hasPendingRecordingAfterOnboarding = false
        return VoiceInkLaunchRecordingRequestPlan(action: .startRecordingAfterLaunchDelay)
    }

    public mutating func consumePendingRecordingIfReady(
        hasCompletedOnboarding: Bool
    ) -> VoiceInkLaunchRecordingRequestPlan {
        guard hasCompletedOnboarding, hasPendingRecordingAfterOnboarding else {
            return VoiceInkLaunchRecordingRequestPlan(action: .none)
        }

        hasPendingRecordingAfterOnboarding = false
        return VoiceInkLaunchRecordingRequestPlan(action: .startRecordingAfterLaunchDelay)
    }
}

public struct VoiceInkKeyboardRecordingButtonPresentation: Equatable, Sendable {
    public let title: String
    public let systemImageName: String

    public init(title: String, systemImageName: String) {
        self.title = title
        self.systemImageName = systemImageName
    }

    public static let idle = VoiceInkKeyboardRecordingButtonPresentation(
        title: " Record",
        systemImageName: "mic.fill"
    )

    public static let recording = VoiceInkKeyboardRecordingButtonPresentation(
        title: " Stop",
        systemImageName: "stop.fill"
    )

    public static let openAppFallback = VoiceInkKeyboardRecordingButtonPresentation(
        title: " Open \(VoiceInkAppIdentity.displayName)",
        systemImageName: "app"
    )

    public static func current(isRecording: Bool) -> VoiceInkKeyboardRecordingButtonPresentation {
        isRecording ? recording : idle
    }
}

enum VoiceInkKeyboardRecordingButtonTapAction: Equatable, Sendable {
    case requestStopRecording
    case openMainAppForRecording
}

public struct VoiceInkKeyboardRecordingButtonTapPlan: Sendable {
    private let action: VoiceInkKeyboardRecordingButtonTapAction
    private let shouldRefreshButtonStateAfterAction: Bool

    init(
        action: VoiceInkKeyboardRecordingButtonTapAction,
        shouldRefreshButtonStateAfterAction: Bool
    ) {
        self.action = action
        self.shouldRefreshButtonStateAfterAction = shouldRefreshButtonStateAfterAction
    }

    public func applyRuntimeState(
        requestStopRecording: () -> Void,
        openMainAppForRecording: () -> Void,
        refreshButtonState: () -> Void
    ) {
        switch action {
        case .requestStopRecording:
            requestStopRecording()
            if shouldRefreshButtonStateAfterAction {
                refreshButtonState()
            }
        case .openMainAppForRecording:
            openMainAppForRecording()
        }
    }
}

public enum VoiceInkKeyboardRecordingButtonTapPolicy {
    public static func plan(isRecording: Bool) -> VoiceInkKeyboardRecordingButtonTapPlan {
        if isRecording {
            return VoiceInkKeyboardRecordingButtonTapPlan(
                action: .requestStopRecording,
                shouldRefreshButtonStateAfterAction: true
            )
        }

        return VoiceInkKeyboardRecordingButtonTapPlan(
            action: .openMainAppForRecording,
            shouldRefreshButtonStateAfterAction: false
        )
    }
}

enum VoiceInkKeyboardOpenAppAction: Equatable, Sendable {
    case openExtensionContext
    case openThroughApplicationOrResponderChain
    case finish
    case showFallback

    func applyRuntimeState(
        openExtensionContext: () -> Void,
        openThroughApplicationOrResponderChain: () -> Void,
        finish: () -> Void,
        showFallback: () -> Void
    ) {
        switch self {
        case .openExtensionContext:
            openExtensionContext()
        case .openThroughApplicationOrResponderChain:
            openThroughApplicationOrResponderChain()
        case .finish:
            finish()
        case .showFallback:
            showFallback()
        }
    }
}

enum VoiceInkKeyboardOpenAppDiagnosticLevel: Equatable, Sendable {
    case notice
    case error
}

enum VoiceInkKeyboardOpenAppDiagnosticTiming: Equatable, Sendable {
    case beforeAction
    case afterAction
}

struct VoiceInkKeyboardOpenAppDiagnosticEvent: Equatable, Sendable {
    let level: VoiceInkKeyboardOpenAppDiagnosticLevel
    let message: String

    init(level: VoiceInkKeyboardOpenAppDiagnosticLevel, message: String) {
        self.level = level
        self.message = message
    }

    func applyRuntimeState(
        logNotice: (String) -> Void,
        logError: (String) -> Void
    ) {
        switch level {
        case .notice:
            logNotice(message)
        case .error:
            logError(message)
        }
    }
}

public struct VoiceInkKeyboardOpenAppActionPlan: Sendable {
    private let action: VoiceInkKeyboardOpenAppAction
    private let diagnosticEvent: VoiceInkKeyboardOpenAppDiagnosticEvent?
    private let diagnosticTiming: VoiceInkKeyboardOpenAppDiagnosticTiming

    init(
        action: VoiceInkKeyboardOpenAppAction,
        diagnosticEvent: VoiceInkKeyboardOpenAppDiagnosticEvent? = nil,
        diagnosticTiming: VoiceInkKeyboardOpenAppDiagnosticTiming = .beforeAction
    ) {
        self.action = action
        self.diagnosticEvent = diagnosticEvent
        self.diagnosticTiming = diagnosticTiming
    }

    public func applyRuntimeState(
        logNotice: (String) -> Void,
        logError: (String) -> Void,
        openExtensionContext: () -> Void,
        openThroughApplicationOrResponderChain: () -> Void,
        finish: () -> Void,
        showFallback: () -> Void
    ) {
        if diagnosticTiming == .beforeAction {
            diagnosticEvent?.applyRuntimeState(logNotice: logNotice, logError: logError)
        }

        action.applyRuntimeState(
            openExtensionContext: openExtensionContext,
            openThroughApplicationOrResponderChain: openThroughApplicationOrResponderChain,
            finish: finish,
            showFallback: showFallback
        )

        if diagnosticTiming == .afterAction {
            diagnosticEvent?.applyRuntimeState(logNotice: logNotice, logError: logError)
        }
    }
}

enum VoiceInkKeyboardOpenAppApplicationAction: Equatable, Sendable {
    case openViaApplication
    case openViaResponderChain

    func applyRuntimeState(
        openViaApplication: () -> Void,
        openViaResponderChain: () -> Void
    ) {
        switch self {
        case .openViaApplication:
            openViaApplication()
        case .openViaResponderChain:
            openViaResponderChain()
        }
    }
}

enum VoiceInkKeyboardOpenAppResponderAction: Equatable, Sendable {
    case performResponderChainOpen
    case showFallback

    func applyRuntimeState(
        performResponderChainOpen: () -> Void,
        showFallback: () -> Void
    ) {
        switch self {
        case .performResponderChainOpen:
            performResponderChainOpen()
        case .showFallback:
            showFallback()
        }
    }
}

public struct VoiceInkKeyboardOpenAppApplicationActionPlan: Sendable {
    private let action: VoiceInkKeyboardOpenAppApplicationAction

    init(action: VoiceInkKeyboardOpenAppApplicationAction) {
        self.action = action
    }

    public func applyRuntimeState(
        openViaApplication: () -> Void,
        openViaResponderChain: () -> Void
    ) {
        action.applyRuntimeState(
            openViaApplication: openViaApplication,
            openViaResponderChain: openViaResponderChain
        )
    }
}

public struct VoiceInkKeyboardOpenAppResponderActionPlan: Sendable {
    private let action: VoiceInkKeyboardOpenAppResponderAction
    private let diagnosticEvent: VoiceInkKeyboardOpenAppDiagnosticEvent?
    private let diagnosticTiming: VoiceInkKeyboardOpenAppDiagnosticTiming

    init(
        action: VoiceInkKeyboardOpenAppResponderAction,
        diagnosticEvent: VoiceInkKeyboardOpenAppDiagnosticEvent? = nil,
        diagnosticTiming: VoiceInkKeyboardOpenAppDiagnosticTiming = .beforeAction
    ) {
        self.action = action
        self.diagnosticEvent = diagnosticEvent
        self.diagnosticTiming = diagnosticTiming
    }

    public func applyRuntimeState(
        logNotice: (String) -> Void,
        logError: (String) -> Void,
        performResponderChainOpen: () -> Void,
        showFallback: () -> Void
    ) {
        if diagnosticTiming == .beforeAction {
            diagnosticEvent?.applyRuntimeState(logNotice: logNotice, logError: logError)
        }

        action.applyRuntimeState(
            performResponderChainOpen: performResponderChainOpen,
            showFallback: showFallback
        )

        if diagnosticTiming == .afterAction {
            diagnosticEvent?.applyRuntimeState(logNotice: logNotice, logError: logError)
        }
    }
}

public enum VoiceInkKeyboardOpenAppPolicy {
    private static func notice(_ message: String) -> VoiceInkKeyboardOpenAppDiagnosticEvent {
        VoiceInkKeyboardOpenAppDiagnosticEvent(level: .notice, message: message)
    }

    private static func error(_ message: String) -> VoiceInkKeyboardOpenAppDiagnosticEvent {
        VoiceInkKeyboardOpenAppDiagnosticEvent(level: .error, message: message)
    }

    public static func initialActionPlan(hasExtensionContext: Bool) -> VoiceInkKeyboardOpenAppActionPlan {
        hasExtensionContext
            ? VoiceInkKeyboardOpenAppActionPlan(action: .openExtensionContext)
            : VoiceInkKeyboardOpenAppActionPlan(
                action: .openThroughApplicationOrResponderChain,
                diagnosticEvent: error(VoiceInkKeyboardOpenAppDiagnostics.extensionContextUnavailable)
            )
    }

    public static func actionPlanAfterExtensionContextOpen(
        succeeded: Bool
    ) -> VoiceInkKeyboardOpenAppActionPlan {
        succeeded
            ? VoiceInkKeyboardOpenAppActionPlan(
                action: .finish,
                diagnosticEvent: notice(VoiceInkKeyboardOpenAppDiagnostics.openedViaExtensionContext)
            )
            : VoiceInkKeyboardOpenAppActionPlan(
                action: .openThroughApplicationOrResponderChain,
                diagnosticEvent: error(VoiceInkKeyboardOpenAppDiagnostics.extensionContextOpenFailed)
            )
    }

    public static func applicationActionPlan(
        canOpenURL: Bool
    ) -> VoiceInkKeyboardOpenAppApplicationActionPlan {
        VoiceInkKeyboardOpenAppApplicationActionPlan(
            action: canOpenURL ? .openViaApplication : .openViaResponderChain
        )
    }

    public static func actionPlanAfterApplicationOpen(
        succeeded: Bool
    ) -> VoiceInkKeyboardOpenAppActionPlan {
        succeeded
            ? VoiceInkKeyboardOpenAppActionPlan(
                action: .finish,
                diagnosticEvent: notice(VoiceInkKeyboardOpenAppDiagnostics.openedViaApplication)
            )
            : VoiceInkKeyboardOpenAppActionPlan(
                action: .showFallback,
                diagnosticEvent: error(VoiceInkKeyboardOpenAppDiagnostics.applicationOpenFailed)
            )
    }

    public static func responderActionPlan(
        hasResponder: Bool
    ) -> VoiceInkKeyboardOpenAppResponderActionPlan {
        hasResponder
            ? VoiceInkKeyboardOpenAppResponderActionPlan(
                action: .performResponderChainOpen,
                diagnosticEvent: notice(VoiceInkKeyboardOpenAppDiagnostics.attemptedViaResponderChain),
                diagnosticTiming: .afterAction
            )
            : VoiceInkKeyboardOpenAppResponderActionPlan(
                action: .showFallback,
                diagnosticEvent: error(VoiceInkKeyboardOpenAppDiagnostics.allMethodsFailed)
            )
    }

}

public enum VoiceInkKeyboardOpenAppDiagnostics {
    public static let extensionContextUnavailable = "extensionContext unavailable, trying alternative methods"
    public static let openedViaExtensionContext = "Opened main app via extensionContext"
    public static let extensionContextOpenFailed = "extensionContext.open failed, trying alternative methods"
    public static let openedViaApplication = "Opened main app via UIApplication.open"
    public static let applicationOpenFailed = "UIApplication.open failed"
    public static let attemptedViaResponderChain = "Attempted to open main app via responder chain"
    public static let allMethodsFailed = "All URL opening methods failed"
}

enum VoiceInkKeyboardStopRecordingRequestAction: Equatable, Sendable {
    case handleStopRequest
    case ignore

    func applyRuntimeState(handleStopRequest: () -> Void) {
        switch self {
        case .handleStopRequest:
            handleStopRequest()
        case .ignore:
            return
        }
    }
}

public struct VoiceInkKeyboardStopRecordingRequestPlan: Sendable {
    private let action: VoiceInkKeyboardStopRecordingRequestAction

    init(action: VoiceInkKeyboardStopRecordingRequestAction) {
        self.action = action
    }

    public func applyRuntimeState(handleStopRequest: () -> Void) {
        action.applyRuntimeState(handleStopRequest: handleStopRequest)
    }
}

public enum VoiceInkKeyboardStopRecordingRequestPolicy {
    public static func plan(
        recordingState: VoiceInkRecordingState
    ) -> VoiceInkKeyboardStopRecordingRequestPlan {
        VoiceInkKeyboardStopRecordingRequestPlan(
            action: recordingState.isActivelyRecording ? .handleStopRequest : .ignore
        )
    }
}

public enum VoiceInkRecorderStyle: String, CaseIterable, Identifiable, Sendable {
    case none
    case notch
    case mini

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none:
            return "None"
        case .notch:
            return "Notch"
        case .mini:
            return "Mini"
        }
    }
}

enum VoiceInkRecorderWindowKind: Equatable, Sendable {
    case none
    case notch
    case mini

    func applyRuntimeState(
        none: () -> Void,
        notch: () -> Void,
        mini: () -> Void
    ) {
        switch self {
        case .none:
            none()
        case .notch:
            notch()
        case .mini:
            mini()
        }
    }
}

public struct VoiceInkMacOSRecorderStyleSettingsPresentation: Equatable, Sendable {
    public let sectionTitle: String
    public let pickerTitle: String

    public init(sectionTitle: String, pickerTitle: String) {
        self.sectionTitle = sectionTitle
        self.pickerTitle = pickerTitle
    }
}

public enum VoiceInkRecorderStylePreference {
    public static let userDefaultsKey = "RecorderType"
    public static let defaultStyle: VoiceInkRecorderStyle = .none
    public static let defaultRawValue = defaultStyle.rawValue
    public static let macOSSettingsPresentation = VoiceInkMacOSRecorderStyleSettingsPresentation(
        sectionTitle: "Interface",
        pickerTitle: "Recorder Style"
    )

    public static func rawValue(from defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: userDefaultsKey) ?? defaultRawValue
    }

    public static func saveRawValue(
        _ rawValue: String,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(rawValue, forKey: userDefaultsKey)
    }

    static func windowKind(forRawValue rawValue: String) -> VoiceInkRecorderWindowKind {
        switch rawValue {
        case VoiceInkRecorderStyle.none.rawValue:
            return .none
        case VoiceInkRecorderStyle.notch.rawValue:
            return .notch
        default:
            return .mini
        }
    }

    public static func hasVisibleRecorder(rawValue: String) -> Bool {
        windowKind(forRawValue: rawValue) != .none
    }

    public static func applyWindowRuntimeState(
        forRawValue rawValue: String,
        none: () -> Void = {},
        notch: () -> Void,
        mini: () -> Void
    ) {
        windowKind(forRawValue: rawValue).applyRuntimeState(
            none: none,
            notch: notch,
            mini: mini
        )
    }
}

public struct VoiceInkRecordingSheetPresentation: Equatable, Sendable {
    public let cancelButtonTitle: String
    public let stopButtonTitle: String
    public let stopButtonSystemImageName: String

    public static let iOS = VoiceInkRecordingSheetPresentation(
        cancelButtonTitle: "Cancel",
        stopButtonTitle: "Stop Recording",
        stopButtonSystemImageName: "stop.fill"
    )
}

public struct VoiceInkRecordingNotificationPresentation: Equatable, Sendable {
    public let title: String
    public let duration: TimeInterval
    public let actionButtonTitle: String?

    public init(
        title: String,
        duration: TimeInterval = 3.0,
        actionButtonTitle: String? = nil
    ) {
        self.title = title
        self.duration = duration
        self.actionButtonTitle = actionButtonTitle
    }

    public static let noTranscriptionModelSelected = VoiceInkRecordingNotificationPresentation(
        title: "No AI Model Selected"
    )

    public static let failedToStart = VoiceInkRecordingNotificationPresentation(
        title: "Recording failed to start"
    )

    public static let microphonePermissionRequired = VoiceInkRecordingNotificationPresentation(
        title: "Microphone permission required",
        duration: 8.0,
        actionButtonTitle: "Grant"
    )

    public static func runtimeFailure(localizedDescription: String) -> VoiceInkRecordingNotificationPresentation {
        VoiceInkRecordingNotificationPresentation(
            title: "Recording Failed: \(localizedDescription)"
        )
    }
}

public struct VoiceInkRecordingAlertPresentation: Equatable, Identifiable, Sendable {
    enum Action: Equatable, Sendable {
        case dismiss
        case openSettings

        func runtimeAction(
            openSettings: @escaping () -> Void
        ) -> (() -> Void)? {
            switch self {
            case .dismiss:
                return nil
            case .openSettings:
                return openSettings
            }
        }
    }

    public static let microphoneInUseOSStatusCode = 561017449
    public static let iOSRecorderStartReturnedFalseDescription = VoiceInkAudioRecorderStartFailurePolicy.returnedFalseDescription

    public let id: String
    public let title: String
    public let message: String
    public let primaryButtonTitle: String
    public let secondaryButtonTitle: String?
    let action: Action

    init(
        id: String,
        title: String,
        message: String,
        primaryButtonTitle: String = "OK",
        secondaryButtonTitle: String? = nil,
        action: Action = .dismiss
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.primaryButtonTitle = primaryButtonTitle
        self.secondaryButtonTitle = secondaryButtonTitle
        self.action = action
    }

    public func runtimeAction(
        openSettings: @escaping () -> Void
    ) -> (() -> Void)? {
        action.runtimeAction(openSettings: openSettings)
    }

    public static var noModesAvailable: VoiceInkRecordingAlertPresentation {
        VoiceInkRecordingAlertPresentation(
            id: "noModesAvailable",
            title: "No Modes Found",
            message: "Please create a new mode in Settings before recording."
        )
    }

    public static var microphonePermissionDenied: VoiceInkRecordingAlertPresentation {
        VoiceInkRecordingAlertPresentation(
            id: "microphonePermissionDenied",
            title: "Microphone Access Denied",
            message: "To record audio, please grant microphone access in Settings.",
            primaryButtonTitle: "Settings",
            secondaryButtonTitle: "Cancel",
            action: .openSettings
        )
    }

    public static var microphoneInUse: VoiceInkRecordingAlertPresentation {
        VoiceInkRecordingAlertPresentation(
            id: "microphoneInUse",
            title: "Microphone In Use",
            message: "Another app is using the microphone. Please try again."
        )
    }

    public static func recordingFailed(localizedDescription: String) -> VoiceInkRecordingAlertPresentation {
        VoiceInkRecordingAlertPresentation(
            id: "recordingFailed-\(localizedDescription)",
            title: "Recording Failed",
            message: "Could not start recording: \(localizedDescription)"
        )
    }

    public static func recordingStartFailure(
        domain: String,
        code: Int,
        localizedDescription: String
    ) -> VoiceInkRecordingAlertPresentation {
        if domain == NSOSStatusErrorDomain && code == microphoneInUseOSStatusCode {
            return microphoneInUse
        }

        return recordingFailed(localizedDescription: localizedDescription)
    }

    public static func recordingStartFailure(for error: Error) -> VoiceInkRecordingAlertPresentation {
        let nsError = error as NSError
        return recordingStartFailure(
            domain: nsError.domain,
            code: nsError.code,
            localizedDescription: error.localizedDescription
        )
    }
}

enum VoiceInkRecordingStartAction: Equatable, Sendable {
    case startRecording
    case presentAlert(VoiceInkRecordingAlertPresentation)

    func applyRuntimeState(
        startRecording: () -> Void,
        presentAlert: (VoiceInkRecordingAlertPresentation) -> Void
    ) {
        switch self {
        case .startRecording:
            startRecording()
        case .presentAlert(let alert):
            presentAlert(alert)
        }
    }
}

public struct VoiceInkRecordingStartPlan: Sendable {
    private let action: VoiceInkRecordingStartAction

    init(action: VoiceInkRecordingStartAction) {
        self.action = action
    }

    public func applyRuntimeState(
        startRecording: () -> Void,
        presentAlert: (VoiceInkRecordingAlertPresentation) -> Void
    ) {
        action.applyRuntimeState(
            startRecording: startRecording,
            presentAlert: presentAlert
        )
    }
}

public enum VoiceInkRecordingStartPolicy {
    public static func plan(modeCount: Int) -> VoiceInkRecordingStartPlan {
        VoiceInkRecordingStartPlan(
            action: modeCount <= 0 ? .presentAlert(.noModesAvailable) : .startRecording
        )
    }
}

public struct VoiceInkMacOSRecordingCancellationPlan: Equatable, Sendable {
    private let shouldClearDeferredStopRequest: Bool
    private let shouldRequestRecordingCancellation: Bool
    private let shouldFinishActiveRecorderCancellation: Bool
    private let shouldClearPartialTranscript: Bool
    private let shouldClearCancelFlag: Bool
    private let recordingStateAfterImmediateCancel: VoiceInkRecordingState?
    private let shouldFinishRecorderSessionImmediately: Bool

    fileprivate init(
        shouldClearDeferredStopRequest: Bool,
        shouldRequestRecordingCancellation: Bool,
        shouldFinishActiveRecorderCancellation: Bool,
        shouldClearPartialTranscript: Bool,
        shouldClearCancelFlag: Bool,
        recordingStateAfterImmediateCancel: VoiceInkRecordingState?,
        shouldFinishRecorderSessionImmediately: Bool
    ) {
        self.shouldClearDeferredStopRequest = shouldClearDeferredStopRequest
        self.shouldRequestRecordingCancellation = shouldRequestRecordingCancellation
        self.shouldFinishActiveRecorderCancellation = shouldFinishActiveRecorderCancellation
        self.shouldClearPartialTranscript = shouldClearPartialTranscript
        self.shouldClearCancelFlag = shouldClearCancelFlag
        self.recordingStateAfterImmediateCancel = recordingStateAfterImmediateCancel
        self.shouldFinishRecorderSessionImmediately = shouldFinishRecorderSessionImmediately
    }

    public func applyRuntimeState(
        clearDeferredStopRequest: () -> Void,
        requestRecordingCancellation: () -> Void,
        finishActiveRecorderCancellation: () async -> Void,
        clearPartialTranscript: () -> Void,
        clearCancelFlag: () -> Void,
        setRecordingState: (VoiceInkRecordingState) -> Void,
        finishRecorderSessionImmediately: () async -> Void
    ) async {
        if shouldClearDeferredStopRequest {
            clearDeferredStopRequest()
        }

        if shouldRequestRecordingCancellation {
            requestRecordingCancellation()
        }

        if shouldFinishActiveRecorderCancellation {
            await finishActiveRecorderCancellation()
        }

        if shouldClearPartialTranscript {
            clearPartialTranscript()
        }

        if shouldClearCancelFlag {
            clearCancelFlag()
        }

        if let recordingStateAfterImmediateCancel {
            setRecordingState(recordingStateAfterImmediateCancel)
        }

        if shouldFinishRecorderSessionImmediately {
            await finishRecorderSessionImmediately()
        }
    }
}

public enum VoiceInkMacOSRecordingCancellationPolicy {
    public static func plan(
        recordingState: VoiceInkRecordingState
    ) -> VoiceInkMacOSRecordingCancellationPlan {
        if recordingState.isRecorderCaptureInProgress {
            return VoiceInkMacOSRecordingCancellationPlan(
                shouldClearDeferredStopRequest: true,
                shouldRequestRecordingCancellation: true,
                shouldFinishActiveRecorderCancellation: true,
                shouldClearPartialTranscript: false,
                shouldClearCancelFlag: false,
                recordingStateAfterImmediateCancel: nil,
                shouldFinishRecorderSessionImmediately: true
            )
        }

        if recordingState.isPostRecordingProcessing {
            return VoiceInkMacOSRecordingCancellationPlan(
                shouldClearDeferredStopRequest: true,
                shouldRequestRecordingCancellation: true,
                shouldFinishActiveRecorderCancellation: false,
                shouldClearPartialTranscript: true,
                shouldClearCancelFlag: false,
                recordingStateAfterImmediateCancel: .idle,
                shouldFinishRecorderSessionImmediately: false
            )
        }

        return VoiceInkMacOSRecordingCancellationPlan(
            shouldClearDeferredStopRequest: true,
            shouldRequestRecordingCancellation: false,
            shouldFinishActiveRecorderCancellation: false,
            shouldClearPartialTranscript: true,
            shouldClearCancelFlag: true,
            recordingStateAfterImmediateCancel: .idle,
            shouldFinishRecorderSessionImmediately: true
        )
    }
}

public extension VoiceInkRecordingState {
    var isActivelyRecording: Bool {
        self == .recording
    }

    var isRecorderCaptureInProgress: Bool {
        self == .starting || self == .recording
    }

    var acceptsRollingBufferPreloadPreview: Bool {
        self == .idle || self == .recording
    }

    var acceptsRecordingShortcutAction: Bool {
        self != .transcribing &&
        self != .enhancing &&
        self != .busy
    }

    var isPostRecordingProcessing: Bool {
        recorderProcessingPresentation != nil
    }

    var isRecorderDismissCancelable: Bool {
        switch self {
        case .starting, .recording, .transcribing, .enhancing:
            return true
        case .idle, .busy:
            return false
        }
    }

    var shouldReturnToIdleWhenActivePipelineFinishes: Bool {
        isPostRecordingProcessing || self == .busy
    }

    private var recorderUIToggleAction: VoiceInkRecorderUIToggleAction {
        switch self {
        case .recording, .starting:
            return .toggleRecord
        case .transcribing, .enhancing:
            return .cancelRecording
        case .idle, .busy:
            return .dismissRecorder
        }
    }

    func applyRecorderUIToggleRuntimeState(
        toggleRecord: () async -> Void,
        cancelRecording: () async -> Void,
        dismissRecorder: () async -> Void
    ) async {
        switch recorderUIToggleAction {
        case .toggleRecord:
            await toggleRecord()
        case .cancelRecording:
            await cancelRecording()
        case .dismissRecorder:
            await dismissRecorder()
        }
    }

    var recorderProcessingPresentation: VoiceInkRecorderProcessingPresentation? {
        switch self {
        case .transcribing:
            return VoiceInkRecorderProcessingPresentation(
                label: "Transcribing",
                progressAnimationInterval: 0.18
            )
        case .enhancing:
            return VoiceInkRecorderProcessingPresentation(
                label: "Enhancing",
                progressAnimationInterval: 0.22
            )
        case .idle, .starting, .recording, .busy:
            return nil
        }
    }
}

public enum VoiceInkRecorderUISessionPolicy {
    public static func isActiveForRecordingShortcut(
        hasVisibleRecorderType: Bool,
        recordingState: VoiceInkRecordingState,
        isRecorderSessionActive: Bool
    ) -> Bool {
        if !hasVisibleRecorderType, recordingState == .idle {
            return false
        }

        return isRecorderSessionActive
    }

    public static func shouldClearStaleHiddenRecorderSession(
        hasVisibleRecorderType: Bool,
        recordingState: VoiceInkRecordingState,
        isRecorderSessionActive: Bool
    ) -> Bool {
        !hasVisibleRecorderType && isRecorderSessionActive && recordingState == .idle
    }
}
