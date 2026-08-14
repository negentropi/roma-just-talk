import Foundation
import SwiftUI
import os
import VoiceInkCore

@MainActor
class RecorderUIManager: ObservableObject {
    @Published var miniRecorderError: String?

    @Published var recorderType: String = VoiceInkRecorderStylePreference.rawValue() {
        didSet {
            if isMiniRecorderVisible {
                destroyWindow(for: oldValue)
                isMiniRecorderVisible = false
            }

            if isRecorderSessionActive, VoiceInkRecorderStylePreference.hasVisibleRecorder(rawValue: recorderType) {
                isMiniRecorderVisible = true
            }
            VoiceInkRecorderStylePreference.saveRawValue(recorderType)
        }
    }

    @Published var isMiniRecorderVisible = false {
        didSet {
            if isMiniRecorderVisible {
                showRecorderPanel()
            } else {
                hideRecorderPanel()
            }
        }
    }
    @Published private(set) var isRecorderSessionActive = false

    var notchWindowManager: NotchWindowManager?
    var miniWindowManager: MiniWindowManager?

    private weak var engine: VoiceInkEngine?
    private var recorder: Recorder?

    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "RecorderUIManager")

    init() {}

    /// Call after VoiceInkEngine is created to break the circular init dependency.
    func configure(engine: VoiceInkEngine, recorder: Recorder) {
        self.engine = engine
        self.recorder = recorder
        setupNotifications()
    }

    // MARK: - Recorder Panel Management

    func showRecorderPanel() {
        guard let engine = engine, let recorder = recorder else { return }
        logger.notice("Showing \(self.recorderType, privacy: .public) recorder")

        VoiceInkRecorderStylePreference.applyWindowRuntimeState(
            forRawValue: recorderType,
            notch: {
                if notchWindowManager == nil {
                    notchWindowManager = NotchWindowManager(engine: engine, recorder: recorder)
                }
                notchWindowManager?.show()
            },
            mini: {
                if miniWindowManager == nil {
                    miniWindowManager = MiniWindowManager(engine: engine, recorder: recorder)
                }
                miniWindowManager?.show()
            }
        )
    }

    func hideRecorderPanel() {
        VoiceInkRecorderStylePreference.applyWindowRuntimeState(
            forRawValue: recorderType,
            notch: { notchWindowManager?.hide() },
            mini: { miniWindowManager?.hide() }
        )
    }

    private func destroyWindow(for recorderType: String) {
        VoiceInkRecorderStylePreference.applyWindowRuntimeState(
            forRawValue: recorderType,
            notch: {
                notchWindowManager?.destroyWindow()
                notchWindowManager = nil
            },
            mini: {
                miniWindowManager?.destroyWindow()
                miniWindowManager = nil
            }
        )
    }

    // MARK: - Mini Recorder Management

    func beginRecorderSession() {
        isRecorderSessionActive = true
        if VoiceInkRecorderStylePreference.hasVisibleRecorder(rawValue: recorderType) {
            isMiniRecorderVisible = true
        } else {
            isMiniRecorderVisible = false
        }
    }

    func isActiveForRecordingShortcut(recordingState: VoiceInkRecordingState) -> Bool {
        VoiceInkRecorderUISessionPolicy.isActiveForRecordingShortcut(
            hasVisibleRecorderType: VoiceInkRecorderStylePreference.hasVisibleRecorder(rawValue: recorderType),
            recordingState: recordingState,
            isRecorderSessionActive: isRecorderSessionActive
        )
    }

    func toggleMiniRecorder(powerModeId: UUID? = nil) async {
        guard let engine = engine else { return }
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTrace.ensureStarted(
            event: "ui.toggle_requested",
            details: "source=non_shortcut state=\(String(describing: engine.recordingState))"
        )
        latencyTrace.event(
            "ui.toggle.enter",
            details: "sessionActive=\(isRecorderSessionActive) visible=\(isMiniRecorderVisible) state=\(String(describing: engine.recordingState))",
            token: traceToken
        )
        logger.notice("toggleMiniRecorder called – sessionActive=\(self.isRecorderSessionActive, privacy: .public), visible=\(self.isMiniRecorderVisible, privacy: .public), state=\(String(describing: engine.recordingState), privacy: .public)")

        if VoiceInkRecorderUISessionPolicy.shouldClearStaleHiddenRecorderSession(
            hasVisibleRecorderType: VoiceInkRecorderStylePreference.hasVisibleRecorder(rawValue: recorderType),
            recordingState: engine.recordingState,
            isRecorderSessionActive: isRecorderSessionActive
        ) {
            logger.notice("toggleMiniRecorder: clearing stale hidden recorder session before starting")
            isRecorderSessionActive = false
        }

        if isRecorderSessionActive {
            await engine.recordingState.applyRecorderUIToggleRuntimeState(
                toggleRecord: {
                    if engine.recordingState == .starting {
                        logger.notice("toggleMiniRecorder: deferring stop while recording starts")
                    } else {
                        logger.notice("toggleMiniRecorder: stopping recording (was recording)")
                    }
                    let span = latencyTrace.begin("ui.engine_toggle", token: traceToken)
                    await engine.toggleRecord(powerModeId: powerModeId)
                    latencyTrace.end(span)
                },
                cancelRecording: {
                    logger.notice("toggleMiniRecorder: cancelling active recorder work")
                    await cancelRecording()
                },
                dismissRecorder: {
                    logger.notice("toggleMiniRecorder: dismissing recorder UI")
                    await dismissMiniRecorder()
                }
            )
        } else {
            let soundSpan = latencyTrace.begin("ui.start_sound", token: traceToken)
            SoundManager.shared.play(.start)
            latencyTrace.end(soundSpan)
            beginRecorderSession()
            latencyTrace.event("ui.recorder_session.begin", token: traceToken)
            let span = latencyTrace.begin("ui.engine_toggle", token: traceToken)
            await engine.toggleRecord(powerModeId: powerModeId)
            latencyTrace.end(span)
        }
    }

    func dismissMiniRecorder() async {
        guard let engine = engine else { return }
        logger.notice("dismissMiniRecorder called – state=\(String(describing: engine.recordingState), privacy: .public)")

        hideRecorderPanel()
        isMiniRecorderVisible = false
        isRecorderSessionActive = false

        logger.notice("dismissMiniRecorder completed")
    }

    func resetOnLaunch() async {
        guard let engine = engine else { return }
        logger.notice("Resetting recording state on launch")
        await engine.resetRecordingSession()
        hideRecorderPanel()
        isMiniRecorderVisible = false
        isRecorderSessionActive = false
        miniRecorderError = nil
    }

    func cancelRecording() async {
        guard let engine = engine else { return }
        logger.notice("cancelRecording called")
        await engine.cancelRecording()
        await dismissMiniRecorder()
    }

    func discardRecording() async {
        guard let engine = engine else { return }
        logger.notice("discardRecording called")
        await engine.discardRecording()
        await dismissMiniRecorder()
    }

    // MARK: - Notification Handling

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleMiniRecorder),
            name: .toggleMiniRecorder,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDismissMiniRecorder),
            name: .dismissMiniRecorder,
            object: nil
        )
    }

    @objc public func handleToggleMiniRecorder() {
        logger.notice("handleToggleMiniRecorder: .toggleMiniRecorder notification received")
        Task {
            await toggleMiniRecorder()
        }
    }

    @objc public func handleDismissMiniRecorder() {
        logger.notice("handleDismissMiniRecorder: .dismissMiniRecorder notification received")
        Task {
            if engine?.recordingState.isRecorderDismissCancelable == true {
                await cancelRecording()
            } else {
                await dismissMiniRecorder()
            }
        }
    }
}
