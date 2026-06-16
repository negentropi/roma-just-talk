import Foundation

enum VoiceInkRetriedUpload {
    private static let retryableStatusCodes: Set<Int> = [429, 500, 502, 503, 504]

    static func upload(
        request: URLRequest,
        body: Data,
        timeout: TimeInterval,
        maxRetries: Int,
        errorDomain: String
    ) async throws -> (Data, URLResponse) {
        let attempts = max(maxRetries, 0)
        var request = request
        request.timeoutInterval = timeout
        var lastError: (any Error)?

        for attempt in 0...attempts {
            if attempt > 0 {
                let delay = UInt64(pow(2.0, Double(attempt - 1)) * 1_000_000_000)
                try await Task.sleep(nanoseconds: delay)
            }

            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = timeout
            configuration.timeoutIntervalForResource = timeout
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
            let session = URLSession(configuration: configuration)
            defer { session.finishTasksAndInvalidate() }

            do {
                let (data, response) = try await session.upload(for: request, from: body)
                if let http = response as? HTTPURLResponse,
                   retryableStatusCodes.contains(http.statusCode),
                   attempt < attempts {
                    lastError = NSError(
                        domain: errorDomain,
                        code: http.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? ""]
                    )
                    continue
                }
                return (data, response)
            } catch {
                lastError = error
                if attempt < attempts {
                    continue
                }
            }
        }

        throw lastError ?? URLError(.unknown)
    }
}
