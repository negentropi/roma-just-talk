import Foundation
import os

public final class VoiceInkLatencyTrace: @unchecked Sendable {
    public struct Token: Hashable, Sendable {
        fileprivate let traceID: String
    }

    public struct Span: Sendable {
        fileprivate let token: Token
        fileprivate let name: String
        fileprivate let startedAt: TimeInterval
    }

    public struct ExecutorCheckpoint: Sendable {
        fileprivate let token: Token
        fileprivate let name: String
        fileprivate let enqueuedAt: TimeInterval

        var enqueuedEventName: String { "\(name).executor_enqueued" }
        var resumedEventName: String { "\(name).executor_resumed" }
    }

    public static let shared = VoiceInkLatencyTrace()

    private struct State {
        let token: Token
        let startedAt: TimeInterval
        var lastEventAt: TimeInterval
        var sequence: Int
        var isFinished: Bool
    }

    private typealias Record = (
        traceID: String,
        sequence: Int,
        totalMilliseconds: Double,
        deltaMilliseconds: Double,
        event: String,
        details: String
    )

    private let lock = NSLock()
    private var state: State?
    private let logger = Logger(
        subsystem: VoiceInkAppIdentity.loggingSubsystem,
        category: VoiceInkMacOSLogCategory.latencyTrace
    )

    private init() {}

    public func currentToken() -> Token? {
        lock.lock()
        let token = state.flatMap { $0.isFinished ? nil : $0.token }
        lock.unlock()
        return token
    }

    public func elapsedMilliseconds(token: Token?, at timestamp: TimeInterval) -> Double? {
        guard let token else { return nil }
        lock.lock()
        guard let state, state.token == token else {
            lock.unlock()
            return nil
        }
        let elapsed = max(0, timestamp - state.startedAt) * 1_000
        lock.unlock()
        return elapsed
    }

    @discardableResult
    public func start(
        event: String,
        details: String = "",
        originTimestamp: TimeInterval? = nil
    ) -> Token {
        let loggedAt = ProcessInfo.processInfo.systemUptime
        let startedAt = min(originTimestamp ?? loggedAt, loggedAt)
        let token = Token(traceID: String(UUID().uuidString.prefix(8)))

        lock.lock()
        let replacedRecord = replacementRecord(at: loggedAt, replacementToken: token)
        state = State(
            token: token,
            startedAt: startedAt,
            lastEventAt: startedAt,
            sequence: 0,
            isFinished: false
        )
        lock.unlock()

        if let replacedRecord {
            emit(replacedRecord)
        }
        emit(
            traceID: token.traceID,
            sequence: 0,
            totalMilliseconds: 0,
            deltaMilliseconds: 0,
            event: event,
            details: details
        )
        return token
    }

    @discardableResult
    public func ensureStarted(event: String, details: String = "") -> Token {
        lock.lock()
        if let state, !state.isFinished {
            let token = state.token
            lock.unlock()
            return token
        }

        let now = ProcessInfo.processInfo.systemUptime
        let token = Token(traceID: String(UUID().uuidString.prefix(8)))
        state = State(
            token: token,
            startedAt: now,
            lastEventAt: now,
            sequence: 0,
            isFinished: false
        )
        lock.unlock()

        emit(
            traceID: token.traceID,
            sequence: 0,
            totalMilliseconds: 0,
            deltaMilliseconds: 0,
            event: event,
            details: details
        )
        return token
    }

    public func event(_ event: String, details: String = "", token: Token?) {
        guard let token,
              let record = makeRecord(
                event: event,
                details: details,
                finish: false,
                token: token
              ) else { return }
        emit(record)
    }

    public func begin(_ name: String, details: String = "", token: Token?) -> Span? {
        guard let token else { return nil }
        let startedAt = ProcessInfo.processInfo.systemUptime
        guard let record = makeRecord(
            event: "\(name).begin",
            details: details,
            finish: false,
            token: token,
            now: startedAt
        ) else { return nil }
        emit(record)
        return Span(token: token, name: name, startedAt: startedAt)
    }

    public func end(_ span: Span?, details: String = "") {
        guard let span else { return }
        let durationMilliseconds = (ProcessInfo.processInfo.systemUptime - span.startedAt) * 1_000
        let durationDetails = joinedDetails(
            "durationMs=\(Self.format(durationMilliseconds))",
            details
        )

        guard let record = makeRecord(
            event: "\(span.name).end",
            details: durationDetails,
            finish: false,
            token: span.token
        ) else { return }
        emit(record)
    }

    public func executorEnqueued(
        _ name: String,
        details: String = "",
        token: Token?
    ) -> ExecutorCheckpoint? {
        executorEnqueued(
            name,
            details: details,
            token: token,
            at: ProcessInfo.processInfo.systemUptime
        )
    }

    func executorEnqueued(
        _ name: String,
        details: String = "",
        token: Token?,
        at timestamp: TimeInterval
    ) -> ExecutorCheckpoint? {
        guard let token else { return nil }
        let checkpoint = ExecutorCheckpoint(
            token: token,
            name: name,
            enqueuedAt: timestamp
        )
        guard let record = makeRecord(
            event: checkpoint.enqueuedEventName,
            details: details,
            finish: false,
            token: token,
            now: timestamp
        ) else { return nil }
        emit(record)
        return checkpoint
    }

    public func executorResumed(
        _ checkpoint: ExecutorCheckpoint?,
        details: String = ""
    ) {
        executorResumed(
            checkpoint,
            details: details,
            at: ProcessInfo.processInfo.systemUptime
        )
    }

    func executorResumed(
        _ checkpoint: ExecutorCheckpoint?,
        details: String = "",
        at timestamp: TimeInterval
    ) {
        guard let checkpoint else { return }
        let resumeDetails = joinedDetails(
            "queueDelayMs=\(Self.format(executorDelayMilliseconds(checkpoint, resumedAt: timestamp)))",
            details
        )
        guard let record = makeRecord(
            event: checkpoint.resumedEventName,
            details: resumeDetails,
            finish: false,
            token: checkpoint.token,
            now: timestamp
        ) else { return }
        emit(record)
    }

    func executorDelayMilliseconds(
        _ checkpoint: ExecutorCheckpoint,
        resumedAt timestamp: TimeInterval
    ) -> Double {
        max(0, timestamp - checkpoint.enqueuedAt) * 1_000
    }

    public func finish(event: String, details: String = "", token: Token?) {
        guard let token,
              let record = makeRecord(
                event: event,
                details: details,
                finish: true,
                token: token
              ) else { return }
        emit(record)
    }

    private func replacementRecord(at now: TimeInterval, replacementToken: Token) -> Record? {
        guard var state, !state.isFinished else { return nil }
        state.sequence += 1
        return (
            traceID: state.token.traceID,
            sequence: state.sequence,
            totalMilliseconds: (now - state.startedAt) * 1_000,
            deltaMilliseconds: (now - state.lastEventAt) * 1_000,
            event: "trace.replaced",
            details: "replacementTrace=\(replacementToken.traceID)"
        )
    }

    private func makeRecord(
        event: String,
        details: String,
        finish: Bool,
        token: Token,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Record? {
        lock.lock()
        guard var state, state.token == token else {
            lock.unlock()
            return nil
        }
        if finish, state.isFinished {
            lock.unlock()
            return nil
        }

        state.sequence += 1
        let record: Record = (
            traceID: token.traceID,
            sequence: state.sequence,
            totalMilliseconds: (now - state.startedAt) * 1_000,
            deltaMilliseconds: (now - state.lastEventAt) * 1_000,
            event: event,
            details: details
        )
        state.lastEventAt = now
        if finish {
            state.isFinished = true
        }
        self.state = state
        lock.unlock()
        return record
    }

    private func emit(_ record: Record) {
        emit(
            traceID: record.traceID,
            sequence: record.sequence,
            totalMilliseconds: record.totalMilliseconds,
            deltaMilliseconds: record.deltaMilliseconds,
            event: record.event,
            details: record.details
        )
    }

    private func emit(
        traceID: String,
        sequence: Int,
        totalMilliseconds: Double,
        deltaMilliseconds: Double,
        event: String,
        details: String
    ) {
        let suffix = details.isEmpty ? "" : " \(details)"
        let message = "[LATENCY] trace=\(traceID) seq=\(sequence) t=\(Self.format(totalMilliseconds))ms delta=\(Self.format(deltaMilliseconds))ms event=\(event)\(suffix)"
        logger.notice("\(message, privacy: .public)")
    }

    private func joinedDetails(_ first: String, _ second: String) -> String {
        second.isEmpty ? first : "\(first) \(second)"
    }

    private static func format(_ milliseconds: Double) -> String {
        String(format: "%.1f", milliseconds)
    }
}
