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
        let frame = CursorAvatarPlacement.frame(anchor: CGRect(x: 990, y: 5, width: 1, height: 16), size: CGSize(width: 180, height: 180), screen: CGRect(x: 0, y: 0, width: 1000, height: 800))
        assert(frame == CGRect(x: 798, y: 7, width: 180, height: 180))
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
        print("PASS readiness ordering, successful-write heartbeat policy, stalled heartbeat policy, write failure policy, primary and secondary display geometry, real monitor callback ordering and stop lifecycle")
    }
}
