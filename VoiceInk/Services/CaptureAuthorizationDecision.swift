@MainActor
enum CaptureAuthorizationDecision {
    static func request(using initiate: (@escaping @Sendable (Bool) -> Void) -> Void) async -> Bool {
        guard !Task.isCancelled else { return false }
        let decisions = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
        initiate { granted in
            decisions.continuation.yield(granted)
            decisions.continuation.finish()
        }
        for await decision in decisions.stream { return decision }
        return false
    }
}
