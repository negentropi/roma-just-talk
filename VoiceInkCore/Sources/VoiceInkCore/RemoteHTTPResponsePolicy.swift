import Foundation

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
