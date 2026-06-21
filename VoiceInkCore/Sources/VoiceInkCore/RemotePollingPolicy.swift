import Foundation

enum VoiceInkRemotePollingDecision<Result> {
    case finished(Result)
    case keepPolling
}

enum VoiceInkRemotePollingPolicy {
    static let defaultIntervalNanoseconds: UInt64 = 1_000_000_000

    static func poll<Result>(
        maxWaitSeconds: TimeInterval,
        pollIntervalNanoseconds: UInt64 = defaultIntervalNanoseconds,
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
        operation: () async throws -> VoiceInkRemotePollingDecision<Result>
    ) async throws -> Result {
        let start = now()

        while true {
            switch try await operation() {
            case .finished(let result):
                return result
            case .keepPolling:
                break
            }

            if now().timeIntervalSince(start) > maxWaitSeconds {
                throw URLError(.timedOut)
            }

            try await sleep(pollIntervalNanoseconds)
        }
    }

    static func pollValidatedData<Result>(
        request: () throws -> URLRequest,
        errorDomain: String,
        maxWaitSeconds: TimeInterval,
        decision: @escaping (Data) throws -> VoiceInkRemotePollingDecision<Result>
    ) async throws -> Result {
        try await poll(maxWaitSeconds: maxWaitSeconds) {
            let request = try request()
            let (data, response) = try await URLSession.shared.data(for: request)
            try VoiceInkRemoteHTTPResponsePolicy.validateSuccess(
                response: response,
                data: data,
                errorDomain: errorDomain
            )
            return try decision(data)
        }
    }
}
