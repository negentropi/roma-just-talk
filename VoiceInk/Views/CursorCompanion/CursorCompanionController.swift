import AppKit
import Combine
import VoiceInkCore

@MainActor
final class CursorCompanionController: ObservableObject {
    @Published var style: VoiceInkCursorCompanionStyle = VoiceInkCursorCompanionPreference.style() {
        didSet {
            VoiceInkCursorCompanionPreference.save(style)
            if style == .none {
                setPhase(.hidden)
            }
        }
    }
    @Published private(set) var phase: VoiceInkCursorCompanionPhase = .hidden
    @Published private(set) var pose: VoiceInkCursorCompanionPose = .perch

    private static let trackingInterval: TimeInterval = 1.0 / 60.0
    // About every 0.12 s at 60 Hz; Accessibility queries are too costly for every frame.
    private static let ticksPerCaretQuery = 7
    private static let smoothing: CGFloat = 0.35
    private static let maximumCaretHeight: CGFloat = 200

    private var cancellables = Set<AnyCancellable>()
    private weak var recorder: Recorder?
    private var captureFlow: VoiceInkCaptureFlowMonitor?
    private var animationTimer: Task<Void, Never>?
    private var panel: CursorCompanionPanel?
    private var trackingTimer: Timer?
    private var tickCount = 0
    /// Caret rect in Cocoa global coordinates.
    private var caretRect: CGRect?
    private var panelOrigin: CGPoint?

    func configure(engine: VoiceInkEngine) {
        recorder = engine.recorder
        engine.$recordingState
            .scan((VoiceInkRecordingState.idle, VoiceInkRecordingState.idle)) { transition, newState in (transition.1, newState) }
            .compactMap { VoiceInkCursorCompanionPolicy.event(from: $0.0, to: $0.1) }
            .sink { [weak self] event in self?.handle(event) }
            .store(in: &cancellables)
        engine.recordingStartFailures
            .sink { [weak self] in self?.handle(.startFailed) }
            .store(in: &cancellables)
    }

    func handle(_ event: VoiceInkCursorCompanionEvent) {
        guard style != .none else { return }
        setPhase(VoiceInkCursorCompanionPolicy.next(phase, on: event))
    }

    private func setPhase(_ next: VoiceInkCursorCompanionPhase) {
        guard next != phase else { return }
        let wasHidden = phase == .hidden
        let wasVisible = phase.isVisible
        phase = next

        animationTimer?.cancel()
        animationTimer = nil
        if let duration = VoiceInkCursorCompanionPolicy.duration(of: next) {
            animationTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(duration))
                guard !Task.isCancelled else { return }
                self?.handle(.animationFinished)
            }
        }

        switch next {
        case .awaitingAudio:
            captureFlow = VoiceInkCaptureFlowMonitor(
                count: recorder?.capturedBufferCount ?? 0,
                now: ProcessInfo.processInfo.systemUptime
            )
        case .hidden, .leaving, .failed:
            captureFlow = nil
        case .arriving, .listening, .stalled:
            break
        }

        if next == .hidden {
            stopTracking()
        } else if wasHidden {
            startTracking()
        } else {
            updatePose()
        }
        if next.isVisible {
            if !wasVisible {
                panelOrigin = nil
                moveToTarget()
            }
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }

    // MARK: - Tracking

    private func startTracking() {
        if panel == nil {
            panel = CursorCompanionPanel(controller: self)
        }
        tickCount = 0
        panelOrigin = nil
        refreshCaret()
        updatePose()
        moveToTarget()

        let timer = Timer(timeInterval: Self.trackingInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    private func stopTracking() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        panel?.orderOut(nil)
        caretRect = nil
        panelOrigin = nil
    }

    private func tick() {
        if var flow = captureFlow, let recorder {
            let event = flow.observe(count: recorder.capturedBufferCount, now: ProcessInfo.processInfo.systemUptime)
            captureFlow = flow
            if let event {
                if event == .audioStalled {
                    let presentation = VoiceInkRecordingNotificationPresentation.microphoneStoppedSendingAudio
                    NotificationManager.shared.showNotification(
                        title: presentation.title,
                        type: .error,
                        duration: presentation.duration
                    )
                }
                handle(event)
            }
        }
        guard phase.isVisible else { return }
        tickCount += 1
        if tickCount.isMultiple(of: Self.ticksPerCaretQuery) {
            refreshCaret()
            updatePose()
        }
        moveToTarget()
    }

    private func refreshCaret() {
        guard let primaryScreenMaxY = NSScreen.screens.first?.frame.maxY,
              let accessibilityRect = CursorTextContextReader.focusedCaretAccessibilityBounds(),
              accessibilityRect.height > 0,
              accessibilityRect.height <= Self.maximumCaretHeight else {
            caretRect = nil
            return
        }
        let rect = CGRect(
            x: accessibilityRect.minX,
            y: primaryScreenMaxY - accessibilityRect.maxY,
            width: accessibilityRect.width,
            height: accessibilityRect.height
        )
        let center = CGPoint(x: rect.midX, y: rect.midY)
        caretRect = NSScreen.screens.contains { $0.frame.contains(center) } ? rect : nil
    }

    private func updatePose() {
        let next: VoiceInkCursorCompanionPose
        switch phase {
        case .failed, .stalled:
            next = .oops
        case .arriving, .listening:
            next = caretRect == nil ? .perch : .hug
        case .hidden, .awaitingAudio, .leaving:
            return
        }
        if pose != next {
            pose = next
        }
    }

    /// Cocoa global point that the artwork anchor should cover.
    private var targetPoint: CGPoint {
        if pose == .hug, let caretRect {
            return CGPoint(x: caretRect.midX, y: caretRect.midY)
        }
        let pointer = NSEvent.mouseLocation
        let offset = CursorCompanionArtwork.perchOffsetFromPointerTip
        return CGPoint(x: pointer.x + offset.width, y: pointer.y - offset.height)
    }

    private func moveToTarget() {
        // The view draws the artwork anchor at the panel's center.
        let size = CursorCompanionPanel.contentSize
        let target = CGPoint(x: targetPoint.x - size.width / 2, y: targetPoint.y - size.height / 2)
        let origin: CGPoint
        if let current = panelOrigin {
            origin = CGPoint(
                x: current.x + (target.x - current.x) * Self.smoothing,
                y: current.y + (target.y - current.y) * Self.smoothing
            )
        } else {
            origin = target
        }
        panelOrigin = origin
        panel?.setFrameOrigin(origin)
    }
}
