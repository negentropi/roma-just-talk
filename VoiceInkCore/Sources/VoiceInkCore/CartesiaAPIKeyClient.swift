import Foundation

public enum VoiceInkCartesiaRequestBuilder {
    public static let apiVersion = "2026-03-01"

    public static func makeVoicesRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.cartesiaVoicesURL(from: baseURL))
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue(apiVersion, forHTTPHeaderField: "Cartesia-Version")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

public struct VoiceInkCartesiaClient: Sendable {
    public init() {}

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

        let request = VoiceInkCartesiaRequestBuilder.makeVoicesRequest(
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
}
