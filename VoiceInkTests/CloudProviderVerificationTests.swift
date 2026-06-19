import Testing
import VoiceInkCore
@testable import VoiceInk

@Suite(.serialized)
struct CloudProviderVerificationTests {
    @Test func coreBackedCloudProvidersShareCoreAPIKeyVerifier() async throws {
        let expectedMappings: [(ModelProvider, VoiceInkProviderKind)] = [
            (.groq, .groq),
            (.deepgram, .deepgram),
            (.elevenLabs, .elevenLabs),
            (.mistral, .mistral),
            (.gemini, .gemini),
            (.soniox, .soniox),
            (.speechmatics, .speechmatics),
            (.assemblyAI, .assemblyAI),
            (.xai, .xai)
        ]
        let verifier = VoiceInkProviderAPIKeyVerifier()

        for (modelProvider, providerKind) in expectedMappings {
            let transcriptionProvider = try #require(modelProvider.coreTranscriptionModelProvider)
            #expect(transcriptionProvider.providerKind == providerKind)

            #expect(CloudProviderRegistry.provider(for: modelProvider) != nil)
            let result = await verifier.verifyAPIKeyDetailed(" \n\t ", for: providerKind)

            #expect(result.isValid == false)
            #expect(result.errorMessage == "API key is missing or empty.")
        }
    }

    @Test func cartesiaKeepsStreamingOnlyVerificationAdapter() async throws {
        #expect(ModelProvider.cartesia.coreTranscriptionModelProvider == .cartesia)
        #expect(ModelProvider.cartesia.coreTranscriptionModelProvider?.providerKind == nil)

        #expect(CloudProviderRegistry.provider(for: .cartesia) != nil)
        let result = await VoiceInkProviderAPIKeyVerifier().verifyAPIKeyDetailed(" \n\t ", for: .cartesia)

        #expect(result.isValid == false)
        #expect(result.errorMessage == "API key is missing or empty.")
    }
}
