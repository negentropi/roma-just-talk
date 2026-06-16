import Foundation

public struct VoiceInkElevenLabsTranscriptionClient: Sendable {
    private static let retryableStatusCodes: Set<Int> = [429, 500, 502, 503, 504]

    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String = "audio.wav",
        language: String? = nil,
        errorDomain: String = "ElevenLabsAPI",
        timeout: TimeInterval = 30,
        maxRetries: Int = 2
    ) async throws -> String {
        let preparedRequest = VoiceInkElevenLabsRequestBuilder.makeTranscriptionRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            audioData: audioData,
            fileName: fileName,
            language: language,
            timeout: timeout
        )

        let (data, response) = try await Self.upload(
            request: preparedRequest.request,
            body: preparedRequest.body,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200..<300).contains(http.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: errorDomain,
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: errorText]
            )
        }

        return try VoiceInkElevenLabsTranscriptionCodec.transcript(from: data)
    }

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await verifyAPIKeyDetailed(baseURL: baseURL, apiKey: apiKey).isValid
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> VoiceInkAPIKeyVerificationResult {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: "API key is missing or empty."
            )
        }

        let request = VoiceInkElevenLabsRequestBuilder.makeUserRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            timeout: timeout
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return VoiceInkAPIKeyVerificationResult(
                    isValid: false,
                    errorMessage: "No HTTP response received."
                )
            }
            if (200..<300).contains(http.statusCode) {
                return VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: nil)
            }
            return VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            )
        } catch {
            return VoiceInkAPIKeyVerificationResult(
                isValid: false,
                errorMessage: error.localizedDescription
            )
        }
    }

    private static func upload(
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
