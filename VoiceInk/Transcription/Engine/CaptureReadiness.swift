import Foundation

struct CaptureReadiness {
    let activationID: UUID
    private(set) var receivedLiveAudio = false
    private(set) var prepared = false

    var isReady: Bool { receivedLiveAudio && prepared }
    mutating func receiveLiveAudio() { receivedLiveAudio = true }
    mutating func prepare() { prepared = true }
}

struct CaptureHealth {
    var lastWrite: TimeInterval?
    var failure: String?

    enum Status: Equatable {
        case waiting, receiving, failed(String)
    }

    func status(now: TimeInterval, startedAt: TimeInterval) -> Status {
        if let failure { return .failed(failure) }
        if now - (lastWrite ?? startedAt) > 2 {
            return .failed("Microphone stopped sending audio. Check your input and try again.")
        }
        return lastWrite == nil ? .waiting : .receiving
    }
}

@MainActor
final class CaptureHealthMonitor {
    private var timer: Timer?
    private var active = true
    private var readySent = false
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private let snapshot: () -> CaptureHealth
    private let onReady: () -> Void
    private let onFailure: (String) -> Void

    init(snapshot: @escaping () -> CaptureHealth, onReady: @escaping () -> Void,
         onFailure: @escaping (String) -> Void) {
        self.snapshot = snapshot
        self.onReady = onReady
        self.onFailure = onFailure
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        active = false
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard active else { return }
        switch snapshot().status(now: ProcessInfo.processInfo.systemUptime, startedAt: startedAt) {
        case .waiting:
            break
        case .receiving:
            if !readySent {
                readySent = true
                onReady()
            }
        case .failed(let message):
            stop()
            onFailure(message)
        }
    }

    deinit { timer?.invalidate() }
}
