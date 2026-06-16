import Foundation
import VoiceInkCore

class OpenAICompatibleTranscriptionService {
    func transcribe(audioURL: URL, model: CustomCloudModel) async throws -> String {
        guard let url = URL(string: model.apiEndpoint) else {
            throw NSError(domain: "CustomWhisperTranscriptionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid API endpoint URL"])
        }

        let preparedRequest = try buildPreparedRequest(audioURL: audioURL, model: model, url: url)
        let (data, response) = try await URLSession.shared.upload(
            for: preparedRequest.request,
            from: preparedRequest.body
        )

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

    private func buildPreparedRequest(
        audioURL: URL,
        model: CustomCloudModel,
        url: URL
    ) throws -> VoiceInkPreparedOpenAICompatibleTranscriptionRequest {
        guard let audioData = try? Data(contentsOf: audioURL) else {
            throw CloudTranscriptionError.audioFileNotFound
        }

        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        let prompt = UserDefaults.standard.string(forKey: "TranscriptionPrompt") ?? ""
        return VoiceInkOpenAICompatibleTranscriptionRequestBuilder.make(
            url: url,
            apiKey: model.apiKey,
            audioData: audioData,
            fileName: audioURL.lastPathComponent,
            model: model.modelName,
            language: selectedLanguage == "auto" ? nil : selectedLanguage,
            prompt: prompt,
            responseFormat: "json",
            temperature: "0"
        )
    }
}
