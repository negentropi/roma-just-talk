import Testing
import RomaCore
@testable import RomaJustTalk

@Suite(.serialized)
struct CloudProviderVerificationTests {
    @Test func coreBackedCloudProvidersShareCoreAPIKeyVerifier() async throws {
        let expectedMappings: [(RomaMacOSTranscriptionModelProvider, RomaProviderKind)] = [
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
        let verifier = RomaProviderAPIKeyVerifier()

        for (modelProvider, providerKind) in expectedMappings {
            let transcriptionProvider = try #require(modelProvider.coreTranscriptionModelProvider)
            #expect(transcriptionProvider.providerKind == providerKind)

            let result = await verifier.verifyAPIKeyDetailed(" \n\t ", for: providerKind)

            #expect(result.isValid == false)
            #expect(result.errorMessage == "API key is missing or empty.")
        }
    }

    @Test func cartesiaKeepsStreamingOnlyVerificationAdapter() async throws {
        #expect(RomaMacOSTranscriptionModelProvider.cartesia.coreTranscriptionModelProvider == .cartesia)
        #expect(RomaMacOSTranscriptionModelProvider.cartesia.coreTranscriptionModelProvider?.providerKind == nil)

        #expect(CloudProviderRegistry.provider(for: .cartesia) != nil)
        let result = await RomaProviderAPIKeyVerifier().verifyAPIKeyDetailed(
            " \n\t ",
            for: RomaTranscriptionModelProvider.cartesia
        )

        #expect(result.isValid == false)
        #expect(result.errorMessage == "API key is missing or empty.")
    }
}
