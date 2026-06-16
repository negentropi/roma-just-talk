import Foundation

public struct VoiceInkOpenAICompatibleTranscriptionClient: Sendable {
    private static let retryableStatusCodes: Set<Int> = [429, 500, 502, 503, 504]

    private let modelsClient: VoiceInkOpenAICompatibleClient

    public init(modelsClient: VoiceInkOpenAICompatibleClient = VoiceInkOpenAICompatibleClient()) {
        self.modelsClient = modelsClient
    }

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String,
        language: String? = nil,
        prompt: String? = nil,
        responseFormat: String? = nil,
        temperature: String? = nil,
        errorDomain: String = "OpenAICompatibleTranscriptionAPI",
        timeout: TimeInterval? = nil,
        maxRetries: Int = 0
    ) async throws -> String {
        let preparedRequest = VoiceInkOpenAICompatibleTranscriptionRequestBuilder.make(
            baseURL: baseURL,
            apiKey: apiKey,
            audioData: audioData,
            fileName: fileName,
            model: model,
            language: language,
            prompt: prompt,
            responseFormat: responseFormat,
            temperature: temperature
        )

        let (data, response) = try await Self.data(
            for: preparedRequest.requestWithHTTPBody(),
            timeout: timeout,
            maxRetries: maxRetries
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

        if let text = try? VoiceInkOpenAICompatibleTranscriptionCodec.textIfPresent(from: data) {
            return text
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await modelsClient.verifyAPIKey(baseURL: baseURL, apiKey: apiKey)
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> VoiceInkAPIKeyVerificationResult {
        await modelsClient.verifyAPIKeyDetailed(
            baseURL: baseURL,
            apiKey: apiKey,
            timeout: timeout
        )
    }

    private static func data(
        for request: URLRequest,
        timeout: TimeInterval?,
        maxRetries: Int
    ) async throws -> (Data, URLResponse) {
        let attempts = max(maxRetries, 0)
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
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse,
                   retryableStatusCodes.contains(http.statusCode),
                   attempt < attempts {
                    lastError = NSError(
                        domain: "OpenAICompatibleTranscriptionAPI",
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
