import Foundation

public struct VoiceInkSpeechmaticsTranscriptionClient: Sendable {
    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String = "audio.wav",
        language: String? = nil,
        operatingPoint: String = "enhanced",
        customVocabulary: [String] = [],
        maxWaitSeconds: TimeInterval = 300,
        timeout: TimeInterval = 30,
        maxRetries: Int = 2,
        errorDomain: String = VoiceInkTranscriptionModelProvider.speechmatics.requiredAPIErrorDomain
    ) async throws -> String {
        let jobID = try await submitJob(
            baseURL: baseURL,
            apiKey: apiKey,
            audioData: audioData,
            fileName: fileName,
            language: language,
            operatingPoint: operatingPoint,
            customVocabulary: customVocabulary,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        try await pollJobStatus(
            baseURL: baseURL,
            apiKey: apiKey,
            id: jobID,
            maxWaitSeconds: maxWaitSeconds,
            timeout: timeout,
            errorDomain: errorDomain
        )
        return try await fetchTranscript(
            baseURL: baseURL,
            apiKey: apiKey,
            id: jobID,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
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

        let request = VoiceInkSpeechmaticsRequestBuilder.makeJobsRequest(
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

    private func submitJob(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String,
        language: String?,
        operatingPoint: String,
        customVocabulary: [String],
        timeout: TimeInterval,
        maxRetries: Int,
        errorDomain: String
    ) async throws -> String {
        let preparedRequest = try VoiceInkSpeechmaticsRequestBuilder.makeSubmitJobRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            audioData: audioData,
            fileName: fileName,
            language: language,
            operatingPoint: operatingPoint,
            customVocabulary: customVocabulary,
            timeout: timeout
        )
        let (data, response) = try await VoiceInkRetriedRequest.upload(
            request: preparedRequest.request,
            body: preparedRequest.body,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        try Self.validate(response: response, data: data, errorDomain: errorDomain)
        return try VoiceInkSpeechmaticsTranscriptionCodec.submittedJobID(from: data)
    }

    private func pollJobStatus(
        baseURL: URL,
        apiKey: String,
        id: String,
        maxWaitSeconds: TimeInterval,
        timeout: TimeInterval,
        errorDomain: String
    ) async throws {
        let start = Date()
        while true {
            let request = VoiceInkSpeechmaticsRequestBuilder.makeJobStatusRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                id: id,
                timeout: timeout
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.validate(response: response, data: data, errorDomain: errorDomain)

            if let status = try? VoiceInkSpeechmaticsTranscriptionCodec.jobStatus(from: data).lowercased() {
                switch status {
                case "done":
                    return
                case "rejected":
                    throw NSError(
                        domain: errorDomain,
                        code: 500,
                        userInfo: [NSLocalizedDescriptionKey: "Speechmatics transcription job was rejected."]
                    )
                case "deleted":
                    throw NSError(
                        domain: errorDomain,
                        code: 410,
                        userInfo: [NSLocalizedDescriptionKey: "Speechmatics transcription job was deleted."]
                    )
                default:
                    break
                }
            }

            if Date().timeIntervalSince(start) > maxWaitSeconds {
                throw URLError(.timedOut)
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func fetchTranscript(
        baseURL: URL,
        apiKey: String,
        id: String,
        timeout: TimeInterval,
        maxRetries: Int,
        errorDomain: String
    ) async throws -> String {
        let request = VoiceInkSpeechmaticsRequestBuilder.makeTranscriptRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            id: id,
            timeout: timeout
        )
        let (data, response) = try await VoiceInkRetriedRequest.data(
            for: request,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        try Self.validate(response: response, data: data, errorDomain: errorDomain)
        return VoiceInkSpeechmaticsTranscriptionCodec.transcript(from: data)
    }

    private static func validate(
        response: URLResponse,
        data: Data,
        errorDomain: String
    ) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(
                domain: errorDomain,
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? ""]
            )
        }
    }
}
