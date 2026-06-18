import Foundation
@testable import VoiceInkCore

final class ProviderModelSelectionTests: XCTestCase {
    func testBundledVoiceInkProviderHasNoSelectableModelsUntilAnAdapterExists() {
        XCTAssertNil(VoiceInkProviderKind.voiceInk.fixedModel(for: .transcription))
        XCTAssertNil(VoiceInkProviderKind.voiceInk.fixedModel(for: .postProcessing))
        XCTAssertNil(VoiceInkProviderKind.voiceInk.defaultModel(for: .transcription))
        XCTAssertNil(VoiceInkProviderKind.voiceInk.defaultModel(for: .postProcessing))
        XCTAssertEqual(VoiceInkProviderKind.voiceInk.models(for: .transcription), [])
        XCTAssertEqual(VoiceInkProviderKind.voiceInk.models(for: .postProcessing), [])
        XCTAssertEqual(VoiceInkProviderKind.voiceInk.selectedModel("stale-model", for: .transcription), "")
        XCTAssertEqual(VoiceInkProviderKind.voiceInk.selectedModel("stale-model", for: .postProcessing), "")
    }

    func testModelSelectionPresentationUsesTranscriptionModelList() {
        XCTAssertEqual(
            VoiceInkProviderKind.deepgram.modelSelectionPresentation(for: .transcription),
            .selectableModels(VoiceInkProviderKind.deepgram.models(for: .transcription))
        )
    }

    func testModelSelectionPresentationUsesPostProcessingModelList() {
        XCTAssertEqual(
            VoiceInkProviderKind.groq.modelSelectionPresentation(for: .postProcessing),
            .selectableModels(VoiceInkAIModelCatalog.availableModels(for: .groq))
        )
    }

    func testModelSelectionPresentationPreservesEmptyBundledProviderList() {
        XCTAssertEqual(
            VoiceInkProviderKind.voiceInk.modelSelectionPresentation(for: .transcription),
            .selectableModels([])
        )
        XCTAssertEqual(
            VoiceInkProviderKind.voiceInk.modelSelectionPresentation(for: .postProcessing),
            .selectableModels([])
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
        XCTAssertNil(VoiceInkProviderKind.voiceInk.postProcessingDefaultModel)
        XCTAssertNil(VoiceInkProviderKind.voiceInk.postProcessingModels)
    }

    func testSelectedModelReturnsEmptyStringWhenUseHasNoModels() {
        XCTAssertEqual(
            VoiceInkProviderKind.cerebras.selectedModel("anything", for: .transcription),
            ""
        )
    }
}
