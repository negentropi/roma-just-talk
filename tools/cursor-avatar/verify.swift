import AppKit

@main
struct Verify {
    @MainActor static func main() async {
        var readiness = CaptureReadiness(activationID: UUID())
        assert(!readiness.isReady, "initial setup is not listening")
        readiness.prepare()
        assert(!readiness.isReady, "prepared session without live capture is not listening")
        readiness.receiveLiveAudio()
        assert(readiness.isReady, "prepared session plus live capture is listening")
        var reversed = CaptureReadiness(activationID: UUID())
        reversed.receiveLiveAudio()
        assert(!reversed.isReady, "live capture before model preparation is not listening")
        reversed.prepare()
        assert(reversed.isReady, "readiness is independent of callback ordering")
        assert(CaptureHealth().status(now: 1, startedAt: 0) == .waiting)
        assert(CaptureHealth(lastWrite: 0.8).status(now: 1, startedAt: 0) == .receiving, "silent successful PCM write counts as capture")
        assert(CaptureHealth(lastWrite: 0.8).status(now: 3, startedAt: 0) == .failed("Microphone stopped sending audio. Check your input and try again."))
        assert(CaptureHealth(lastWrite: 0.8, failure: "Disk full").status(now: 1, startedAt: 0) == .failed("Disk full"))
        let desktop = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let pointer = CursorAvatarPlacement.frame(anchor: CGRect(x: 400, y: 300, width: 0, height: 0), size: CGSize(width: 40, height: 36), screen: desktop)
        assert(pointer.minX + 16 == 400 && pointer.maxY - 32 == 300, "character feet touch the pointer hotspot without a gap")
        let caret = CursorAvatarPlacement.frame(anchor: CGRect(x: 400, y: 300, width: 0, height: 16), size: CGSize(width: 40, height: 36), screen: desktop)
        assert(caret.minX + 16 == 400 && caret.maxY - 32 == 316, "character perches on the blinking caret")
        let frame = CursorAvatarPlacement.frame(anchor: CGRect(x: 990, y: 5, width: 1, height: 16), size: CGSize(width: 224, height: 90), screen: desktop)
        assert(frame == CGRect(x: 786, y: 0, width: 224, height: 90))
        let rightEdge = CursorAvatarPlacement.frame(anchor: CGRect(x: 970, y: 300, width: 0, height: 16), size: CGSize(width: 224, height: 90), screen: desktop)
        assert(rightEdge.minX + 204 == 970 && rightEdge.maxY - 32 == 316, "warning flips left without detaching the character")
        let above = CursorAvatarPlacement.caretToAppKit(CGRect(x: -1200, y: -600, width: 1, height: 20), primaryTop: 900)
        assert(above == CGRect(x: -1200, y: 1480, width: 1, height: 20))
        let screen = CGRect(x: -1280, y: 900, width: 1280, height: 720)
        let clamped = CursorAvatarPlacement.frame(anchor: above, size: CGSize(width: 180, height: 180), screen: screen)
        assert(screen.contains(clamped), "entire panel stays on the secondary display")
        var snapshot = CaptureHealth(lastWrite: ProcessInfo.processInfo.systemUptime)
        var readyCount = 0
        var failures: [String] = []
        let monitor = CaptureHealthMonitor(snapshot: { snapshot }, onReady: { readyCount += 1 },
                                           onFailure: { failures.append($0) })
        try? await Task.sleep(for: .milliseconds(550))
        assert(readyCount == 1, "live monitor emits exactly one readiness receipt")
        snapshot.failure = "Disk full"
        try? await Task.sleep(for: .milliseconds(350))
        assert(failures == ["Disk full"], "live monitor delivers recording failure once")
        try? await Task.sleep(for: .milliseconds(350))
        assert(failures == ["Disk full"], "failed monitor stops itself")
        monitor.stop()
        var staleReady = 0
        let stopped = CaptureHealthMonitor(snapshot: { CaptureHealth(lastWrite: ProcessInfo.processInfo.systemUptime) },
                                           onReady: { staleReady += 1 }, onFailure: { _ in fatalError("stopped monitor fired") })
        stopped.stop()
        try? await Task.sleep(for: .milliseconds(350))
        assert(staleReady == 0, "stopped monitor cannot deliver a stale activation receipt")
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let controller = CursorAvatarController()
        controller.update(.starting)
        guard let panel = application.windows.compactMap({ $0 as? NSPanel }).first(where: { $0.isVisible }) else {
            fatalError("production cursor panel did not appear")
        }
        assert(panel.ignoresMouseEvents, "companion cannot intercept the user's clicks")
        assert(panel.frame.size == CGSize(width: 40, height: 36), "ordinary feedback occupies a tiny cursor attachment")
        assert(panel.styleMask.contains(.nonactivatingPanel), "companion cannot steal keyboard focus")
        assert(!panel.isOpaque && panel.backgroundColor == .clear, "companion has a transparent background")
        assert(NSScreen.screens.contains { $0.visibleFrame.contains(panel.frame) }, "live panel stays within a usable screen")
        controller.update(.failed("Disk full"))
        controller.update(.hidden)
        controller.update(.ready)
        assert(panel.isVisible, "ordinary dismissal cannot hide a capture failure")
        try? await Task.sleep(for: .milliseconds(2300))
        assert(panel.isVisible, "automatic pre-roll readiness cannot replace and dismiss a capture failure")
        controller.update(.starting)
        controller.update(.hidden)
        assert(!panel.isVisible, "explicit new activation clears the previous failure")
        controller.update(.ready)
        try? await Task.sleep(for: .milliseconds(2300))
        assert(!application.windows.contains { $0 is NSPanel && $0.isVisible }, "idle readiness becomes quiet after its greeting")
        print("PASS readiness ordering, successful-write heartbeat policy, stalled heartbeat policy, write failure policy, primary and secondary display geometry, real monitor callback ordering and stop lifecycle")
        print("PASS native panel visibility, click-through, nonactivation, transparency, screen bounds, failure retention and idle dismissal")
    }
}
