import Foundation
import Testing
@testable import VoiceInk

private struct ClaimTestModel: TranscriptionModel {
    let id = UUID()
    let name: String
    let displayName: String
    let description = "Claim test model"
    let provider: ModelProvider = .fluidAudio
    let isMultilingualModel = true
    let supportsStreaming = true
    let supportedLanguages: [String: String] = [:]
}

@MainActor
private final class ClaimTestSession: TranscriptionSession {
    func prepare(model: any TranscriptionModel) async throws -> ((Data) -> Void)? {
        { _ in }
    }

    func transcribe(audioURL: URL) async throws -> String {
        ""
    }

    func cancel() {}
}

@MainActor
struct RollingBufferPreloadClaimTests {
    @Test func claimMatchesSameModelAndLanguage() async {
        let claim = makeClaim(modelName: "same-model", language: "en")
        let model = ClaimTestModel(name: "same-model", displayName: "Same Model")

        #expect(claim.matches(model: model, language: "en"))
    }

    @Test func claimRejectsChangedModel() async {
        let claim = makeClaim(modelName: "old-model", language: "en")
        let model = ClaimTestModel(name: "new-model", displayName: "New Model")

        #expect(!claim.matches(model: model, language: "en"))
    }

    @Test func claimRejectsChangedLanguage() async {
        let claim = makeClaim(modelName: "same-model", language: "en")
        let model = ClaimTestModel(name: "same-model", displayName: "Same Model")

        #expect(!claim.matches(model: model, language: "de"))
    }

    @MainActor
    private func makeClaim(modelName: String, language: String?) -> RollingBufferPreloadClaim {
        RollingBufferPreloadClaim(
            preloaded: RollingBufferPreloadedSession(
                session: ClaimTestSession(),
                audioChunkHandler: { _ in },
                language: language,
                audioData: Data()
            ),
            modelName: modelName,
            language: language
        )
    }
}
