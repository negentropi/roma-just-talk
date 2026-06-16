import Foundation
import VoiceInkCore

class OpenAICompatibleTranscriptionService {
    func transcribe(audioURL: URL, model: CustomCloudModel) async throws -> String {
        guard let url = URL(string: model.apiEndpoint) else {
            throw NSError(domain: "CustomWhisperTranscriptionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid API endpoint URL"])
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(VoiceInkOpenAICompatibleTranscriptionCodec.multipartContentType(boundary: boundary), forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(model.apiKey)", forHTTPHeaderField: "Authorization")

        let body = try buildRequestBody(audioURL: audioURL, modelName: model.modelName, boundary: boundary)
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        do {
            guard let text = try VoiceInkOpenAICompatibleTranscriptionCodec.textIfPresent(from: data) else {
                throw CloudTranscriptionError.noTranscriptionReturned
            }
            return text
        } catch {
            throw CloudTranscriptionError.noTranscriptionReturned
        }
    }

    private func buildRequestBody(audioURL: URL, modelName: String, boundary: String) throws -> Data {
        guard let audioData = try? Data(contentsOf: audioURL) else {
            throw CloudTranscriptionError.audioFileNotFound
        }

        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        let prompt = UserDefaults.standard.string(forKey: "TranscriptionPrompt") ?? ""
        return VoiceInkOpenAICompatibleTranscriptionCodec.requestBody(
            audioData: audioData,
            fileName: audioURL.lastPathComponent,
            model: modelName,
            boundary: boundary,
            language: selectedLanguage == "auto" ? nil : selectedLanguage,
            prompt: prompt,
            responseFormat: "json",
            temperature: "0"
        )
    }
}
