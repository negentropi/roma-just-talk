import VoiceInkCore

extension VoiceInkCloudTranscriptionModelSpec {
    func makeCloudModel(provider: ModelProvider) -> CloudModel {
        CloudModel(
            name: name,
            displayName: displayName,
            description: description,
            provider: provider,
            speed: speed,
            accuracy: accuracy,
            isMultilingual: isMultilingual,
            supportsStreaming: supportsStreaming,
            supportedLanguages: provider.supportedLanguages(isMultilingual: isMultilingual)
        )
    }
}
