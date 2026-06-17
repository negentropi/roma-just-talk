import Foundation
@testable import VoiceInkCore

final class CustomCloudModelPolicyTests: XCTestCase {
    func testGeneratedNamePreservesExistingLowercaseSpaceReplacementPolicy() {
        XCTAssertEqual(
            VoiceInkCustomCloudModelPolicy.generatedName(fromDisplayName: "My Custom Model"),
            "my-custom-model"
        )
    }

    func testNormalizedDraftPreservesCurrentMacOSFormPreparation() {
        let draft = VoiceInkCustomCloudModelPolicy.normalizedDraft(
            displayName: " My Custom Model ",
            apiEndpoint: " https://api.example.com/v1/audio/transcriptions ",
            apiKey: " key ",
            modelName: " whisper-1 "
        )

        XCTAssertEqual(
            draft,
            VoiceInkCustomCloudModelDraft(
                name: "my-custom-model",
                displayName: "My Custom Model",
                apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
                apiKey: "key",
                modelName: "whisper-1"
            )
        )
    }

    func testRequiredFieldPolicyMatchesMacOSButtonEnablement() {
        XCTAssertFalse(
            VoiceInkCustomCloudModelPolicy.hasRequiredFields(
                VoiceInkCustomCloudModelPolicy.normalizedDraft(
                    displayName: " ",
                    apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
                    apiKey: "key",
                    modelName: "whisper-1"
                )
            )
        )

        XCTAssertTrue(
            VoiceInkCustomCloudModelPolicy.hasRequiredFields(
                VoiceInkCustomCloudModelPolicy.normalizedDraft(
                    displayName: "Custom",
                    apiEndpoint: "not a url",
                    apiKey: "key",
                    modelName: "whisper-1"
                )
            )
        )
    }

    func testValidationReturnsExistingMacOSErrorsInOrder() {
        let errors = VoiceInkCustomCloudModelPolicy.validationErrors(
            for: VoiceInkCustomCloudModelDraft(
                name: " ",
                displayName: "",
                apiEndpoint: "not a url",
                apiKey: "\n",
                modelName: " "
            ),
            existingModels: []
        )

        XCTAssertEqual(
            errors,
            [
                "Name cannot be empty",
                "Display name cannot be empty",
                "API endpoint must be a valid URL",
                "API key cannot be empty",
                "Model name cannot be empty"
            ]
        )
    }

    func testValidationRejectsDuplicateNameUnlessEditingSameModel() {
        let id = UUID()
        let draft = VoiceInkCustomCloudModelDraft(
            name: "custom",
            displayName: "Custom",
            apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
            apiKey: "key",
            modelName: "whisper-1"
        )

        XCTAssertEqual(
            VoiceInkCustomCloudModelPolicy.validationErrors(
                for: draft,
                existingModels: [VoiceInkCustomCloudModelIdentity(id: id, name: "custom")]
            ),
            ["A model with this name already exists"]
        )

        XCTAssertEqual(
            VoiceInkCustomCloudModelPolicy.validationErrors(
                for: draft,
                existingModels: [VoiceInkCustomCloudModelIdentity(id: id, name: "custom")],
                excludingId: id
            ),
            []
        )
    }
}
