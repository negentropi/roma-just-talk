import Foundation

struct VoiceInkMultipartFormData {
    let boundary: String
    private var body = Data()

    init(boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    var data: Data {
        var result = body
        append("--\(boundary)--\r\n", to: &result)
        return result
    }

    mutating func addField(name: String, value: String) {
        append("--\(boundary)\r\n", to: &body)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n", to: &body)
        append(value, to: &body)
        append("\r\n", to: &body)
    }

    mutating func addFile(name: String, fileName: String, mimeType: String, fileData: Data) {
        append("--\(boundary)\r\n", to: &body)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n", to: &body)
        append("Content-Type: \(mimeType)\r\n\r\n", to: &body)
        body.append(fileData)
        append("\r\n", to: &body)
    }

    private func append(_ string: String, to data: inout Data) {
        data.append(Data(string.utf8))
    }
}

enum VoiceInkRemoteHTTPResponsePolicy {
    static let successStatusCodeRange = 200..<300
    static let retryableStatusCodes: Set<Int> = [429, 500, 502, 503, 504]

    static func validateSuccess(
        response: URLResponse,
        data: Data,
        errorDomain: String
    ) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard successStatusCodeRange.contains(http.statusCode) else {
            throw apiError(statusCode: http.statusCode, data: data, errorDomain: errorDomain)
        }
    }

    static func retryableStatusCode(in response: URLResponse) -> Int? {
        guard let http = response as? HTTPURLResponse else {
            return nil
        }
        return retryableStatusCodes.contains(http.statusCode) ? http.statusCode : nil
    }

    static func apiError(statusCode: Int, data: Data, errorDomain: String) -> NSError {
        NSError(
            domain: errorDomain,
            code: statusCode,
            userInfo: [NSLocalizedDescriptionKey: responseBodyText(from: data)]
        )
    }

    static func responseBodyText(from data: Data) -> String {
        String(data: data, encoding: .utf8) ?? ""
    }
}

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

    static func validatedData(
        for request: URLRequest,
        timeout: TimeInterval?,
        maxRetries: Int,
        errorDomain: String
    ) async throws -> Data {
        let (data, response) = try await data(
            for: request,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        try VoiceInkRemoteHTTPResponsePolicy.validateSuccess(
            response: response,
            data: data,
            errorDomain: errorDomain
        )
        return data
    }

    static func validatedUpload(
        request: URLRequest,
        body: Data,
        timeout: TimeInterval,
        maxRetries: Int,
        errorDomain: String
    ) async throws -> Data {
        let (data, response) = try await upload(
            request: request,
            body: body,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        try VoiceInkRemoteHTTPResponsePolicy.validateSuccess(
            response: response,
            data: data,
            errorDomain: errorDomain
        )
        return data
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
