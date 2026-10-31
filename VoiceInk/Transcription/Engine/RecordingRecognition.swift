import Foundation

enum RecordingRecognition: Equatable, Sendable {
    case voice(String)
    case lips(String)
    case none

    static func resolve(
        voice: Task<String, Error>?,
        lips: Task<String, Error>?
    ) async throws -> Self {
        try Task.checkCancellation()
        let voiceResult = await voice?.result
        try Task.checkCancellation()
        if case .success(let text) = voiceResult,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Voice wins; release the unused inference process before delivering its text.
            lips?.cancel()
            _ = await lips?.result
            try Task.checkCancellation()
            return .voice(text)
        }

        let lipResult = await lips?.result
        try Task.checkCancellation()
        if case .success(let text) = lipResult,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .lips(text)
        }
        if case .failure(let error) = lipResult { throw error }
        if case .failure(let error) = voiceResult { throw error }
        return .none
    }
}
