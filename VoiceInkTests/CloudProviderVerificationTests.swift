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

        for (modelProvider, providerKind) in expectedMappings {
            #expect(modelProvider.coreTranscriptionModelProvider?.providerKind == providerKind)

            let cloudProvider = try #require(CloudProviderRegistry.provider(for: modelProvider))
            let result = await cloudProvider.verifyAPIKey(" \n\t ")

            #expect(result.isValid == false)
            #expect(result.errorMessage == "API key is missing or empty.")
        }
    }

    @Test func cartesiaKeepsStreamingOnlyVerificationAdapter() async throws {
        #expect(ModelProvider.cartesia.coreTranscriptionModelProvider == .cartesia)
        #expect(ModelProvider.cartesia.coreTranscriptionModelProvider?.providerKind == nil)

        let cloudProvider = try #require(CloudProviderRegistry.provider(for: .cartesia))
        let result = await cloudProvider.verifyAPIKey(" \n\t ")

        #expect(result.isValid == false)
        #expect(result.errorMessage == "API key is missing or empty.")
    }
}
