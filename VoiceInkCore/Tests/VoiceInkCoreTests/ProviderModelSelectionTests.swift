#if canImport(XCTest)
import XCTest
@testable import VoiceInkCore

final class ProviderModelSelectionTests: XCTestCase {
    func testSelectedModelUsesFixedModelWhenProviderHasOne() {
        XCTAssertEqual(
            VoiceInkProviderKind.voiceInk.selectedModel("stale-model", for: .transcription),
            VoiceInkTranscriptionModelCatalog.voiceInkTranscriptionModel
        )
    }

    func testSelectedModelPreservesAvailableCurrentModel() {
        XCTAssertEqual(
            VoiceInkProviderKind.deepgram.selectedModel("nova-3-medical", for: .transcription),
            "nova-3-medical"
        )
    }

    func testSelectedModelFallsBackToProviderDefaultWhenCurrentModelIsUnavailable() {
        XCTAssertEqual(
            VoiceInkProviderKind.gemini.selectedModel("old-gemini-model", for: .postProcessing),
            VoiceInkAIModelCatalog.defaultModel(for: .gemini)
        )
    }

    func testPostProcessingDefaultModelUsesCatalogDefaultForCoreAIProviders() {
        XCTAssertEqual(
            VoiceInkProviderKind.groq.postProcessingDefaultModel,
            VoiceInkAIModelCatalog.defaultModel(for: .groq)
        )
        XCTAssertEqual(
            VoiceInkProviderKind.groq.defaultModel(for: .postProcessing),
            VoiceInkAIModelCatalog.defaultModel(for: .groq)
        )
        XCTAssertEqual(
            VoiceInkProviderKind.openAI.postProcessingDefaultModel,
            VoiceInkAIModelCatalog.defaultModel(for: .openAI)
        )
        XCTAssertEqual(
            VoiceInkProviderKind.cerebras.postProcessingDefaultModel,
            VoiceInkAIModelCatalog.defaultModel(for: .cerebras)
        )
        XCTAssertEqual(
            VoiceInkProviderKind.gemini.postProcessingDefaultModel,
            VoiceInkAIModelCatalog.defaultModel(for: .gemini)
        )
    }

    func testPostProcessingModelListUsesCatalogModelsForCoreAIProviders() {
        XCTAssertEqual(
            VoiceInkProviderKind.groq.postProcessingModels,
            VoiceInkAIModelCatalog.availableModels(for: .groq)
        )
        XCTAssertEqual(
            VoiceInkProviderKind.gemini.postProcessingModels,
            VoiceInkAIModelCatalog.availableModels(for: .gemini)
        )
    }

    func testPostProcessingModelSelectionUsesFixedModelWhenProviderHasOne() {
        XCTAssertEqual(
            VoiceInkProviderKind.voiceInk.postProcessingDefaultModel,
            VoiceInkAIModelCatalog.voiceInkPostProcessingModel
        )
        XCTAssertEqual(
            VoiceInkProviderKind.voiceInk.postProcessingModels,
            [VoiceInkAIModelCatalog.voiceInkPostProcessingModel]
        )
    }

    func testPostProcessingModelsAreNilForNonPostProcessingProviders() {
        XCTAssertNil(VoiceInkProviderKind.deepgram.postProcessingDefaultModel)
        XCTAssertNil(VoiceInkProviderKind.deepgram.postProcessingModels)
        XCTAssertNil(VoiceInkProviderKind.mistral.postProcessingDefaultModel)
        XCTAssertNil(VoiceInkProviderKind.mistral.postProcessingModels)
        XCTAssertNil(VoiceInkProviderKind.elevenLabs.postProcessingDefaultModel)
        XCTAssertNil(VoiceInkProviderKind.elevenLabs.postProcessingModels)
        XCTAssertNil(VoiceInkProviderKind.soniox.postProcessingDefaultModel)
        XCTAssertNil(VoiceInkProviderKind.soniox.postProcessingModels)
        XCTAssertNil(VoiceInkProviderKind.speechmatics.postProcessingDefaultModel)
        XCTAssertNil(VoiceInkProviderKind.speechmatics.postProcessingModels)
        XCTAssertNil(VoiceInkProviderKind.assemblyAI.postProcessingDefaultModel)
        XCTAssertNil(VoiceInkProviderKind.assemblyAI.postProcessingModels)
        XCTAssertNil(VoiceInkProviderKind.xai.postProcessingDefaultModel)
        XCTAssertNil(VoiceInkProviderKind.xai.postProcessingModels)
        XCTAssertNil(VoiceInkProviderKind.localWhisper.postProcessingDefaultModel)
        XCTAssertNil(VoiceInkProviderKind.localWhisper.postProcessingModels)
    }

    func testSelectedModelReturnsEmptyStringWhenUseHasNoModels() {
        XCTAssertEqual(
            VoiceInkProviderKind.cerebras.selectedModel("anything", for: .transcription),
            ""
        )
    }
}
#endif
