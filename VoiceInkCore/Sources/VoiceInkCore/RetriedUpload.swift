import Foundation

enum VoiceInkRetriedRequest {
    static func data(
        for request: URLRequest,
        timeout: TimeInterval?,
        maxRetries: Int,
        errorDomain: String
    ) async throws -> (Data, URLResponse) {
        try await perform(
            request: request,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        ) { session, request in
            try await session.data(for: request)
        }
    }

    static func upload(
        request: URLRequest,
        body: Data,
        timeout: TimeInterval,
        maxRetries: Int,
        errorDomain: String
    ) async throws -> (Data, URLResponse) {
        try await perform(
            request: request,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        ) { session, request in
            try await session.upload(for: request, from: body)
        }
    }

    private static func perform(
        request: URLRequest,
        timeout: TimeInterval?,
        maxRetries: Int,
        errorDomain: String,
        operation: (URLSession, URLRequest) async throws -> (Data, URLResponse)
    ) async throws -> (Data, URLResponse) {
        let attempts = max(maxRetries, 0)
        var request = request
        if let timeout {
            request.timeoutInterval = timeout
        }
        var lastError: (any Error)?

        for attempt in 0...attempts {
            if attempt > 0 {
                let delay = UInt64(pow(2.0, Double(attempt - 1)) * 1_000_000_000)
                try await Task.sleep(nanoseconds: delay)
            }

            let session: URLSession
            if let timeout {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = timeout
                configuration.timeoutIntervalForResource = timeout
                configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
                configuration.urlCache = nil
                session = URLSession(configuration: configuration)
            } else {
                session = .shared
            }
            defer {
                if timeout != nil {
                    session.finishTasksAndInvalidate()
                }
            }

            do {
                let (data, response) = try await operation(session, request)
                if let statusCode = VoiceInkRemoteHTTPResponsePolicy.retryableStatusCode(in: response),
                   attempt < attempts {
                    lastError = VoiceInkRemoteHTTPResponsePolicy.apiError(
                        statusCode: statusCode,
                        data: data,
                        errorDomain: errorDomain
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
