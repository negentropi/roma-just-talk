import Foundation

public struct VoiceInkAPIKeyVerificationResult: Equatable, Sendable {
    public let isValid: Bool
    public let errorMessage: String?

    public init(isValid: Bool, errorMessage: String?) {
        self.isValid = isValid
        self.errorMessage = errorMessage
    }

    public init(legacyResult: (Bool, String?)) {
        self.init(isValid: legacyResult.0, errorMessage: legacyResult.1)
    }
}

enum VoiceInkAPIKeyVerificationPolicy {
    static let missingAPIKeyMessage = "API key is missing or empty."
    static let missingHTTPResponseMessage = "No HTTP response received."

    static func verify(
        apiKey: String,
        request: @autoclosure () -> URLRequest
    ) async -> VoiceInkAPIKeyVerificationResult {
        if let blankResult = blankAPIKeyResultIfNeeded(apiKey) {
            return blankResult
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request())
            return verificationResult(data: data, response: response)
        } catch {
            return failureResult(error)
        }
    }

    static func blankAPIKeyResultIfNeeded(_ apiKey: String) -> VoiceInkAPIKeyVerificationResult? {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? missingAPIKeyResult : nil
    }

    static var missingAPIKeyResult: VoiceInkAPIKeyVerificationResult {
        VoiceInkAPIKeyVerificationResult(isValid: false, errorMessage: missingAPIKeyMessage)
    }

    static func verificationResult(data: Data, response: URLResponse) -> VoiceInkAPIKeyVerificationResult {
        guard let http = response as? HTTPURLResponse else {
            return VoiceInkAPIKeyVerificationResult(isValid: false, errorMessage: missingHTTPResponseMessage)
        }

        guard !VoiceInkRemoteHTTPResponsePolicy.successStatusCodeRange.contains(http.statusCode) else {
            return VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: nil)
        }

        return VoiceInkAPIKeyVerificationResult(
            isValid: false,
            errorMessage: errorMessage(data: data, statusCode: http.statusCode)
        )
    }

    static func failureResult(_ error: Error) -> VoiceInkAPIKeyVerificationResult {
        VoiceInkAPIKeyVerificationResult(isValid: false, errorMessage: error.localizedDescription)
    }

    static func errorMessage(data: Data, statusCode: Int) -> String {
        String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
    }
}
