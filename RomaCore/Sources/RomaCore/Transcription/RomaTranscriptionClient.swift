import Foundation

public struct RomaTranscriptionClient: Sendable {
    public var name: String
    public var service: any TranscriptionService
    public var model: TranscriptionModelDescriptor
    public var details: [String]

    public init(
        name: String,
        service: any TranscriptionService,
        model: TranscriptionModelDescriptor,
        details: [String]
    ) {
        self.name = name
        self.service = service
        self.model = model
        self.details = details
    }

    public static func make(from configuration: RomaWindowsAgentConfiguration) throws -> RomaTranscriptionClient {
        if configuration.usesWhisperCLI {
            let whisperConfiguration = try configuration.whisperCLIConfiguration()
            let modelName = whisperConfiguration.modelURL.lastPathComponent
            return RomaTranscriptionClient(
                name: "whisper.cpp-cli",
                service: WhisperCLITranscriptionService(configuration: whisperConfiguration),
                model: TranscriptionModelDescriptor(
                    name: modelName,
                    displayName: modelName,
                    provider: .whisper
                ),
                details: [
                    "whisper_cli=\(whisperConfiguration.executableURL.path)",
                    "whisper_model=\(whisperConfiguration.modelURL.path)",
                    "whisper_output_dir=\(whisperConfiguration.outputDirectoryURL.path)",
                    "whisper_extra_args=\(whisperConfiguration.extraArguments.count)"
                ]
            )
        }

        let endpointText = try configuration.requireEndpoint()
        let modelName = try configuration.requireModel()
        let apiKeySource = try configuration.apiKeySource()

        return try openAICompatible(
            endpointText: endpointText,
            modelName: modelName,
            apiKeySource: apiKeySource
        )
    }

    public static func openAICompatible(
        endpointText: String,
        modelName: String,
        apiKeySource: TranscriptionAPIKeySource
    ) throws -> RomaTranscriptionClient {
        guard let endpointURL = URL(string: endpointText), endpointURL.scheme != nil else {
            throw RomaCommandLineOptionsError.invalidOptionValue("--endpoint")
        }

        return RomaTranscriptionClient(
            name: "openai-compatible",
            service: OpenAICompatibleTranscriptionService(
                configuration: OpenAICompatibleTranscriptionConfiguration(
                    endpointURL: endpointURL,
                    apiKey: try apiKeySource.resolve()
                )
            ),
            model: TranscriptionModelDescriptor(
                name: modelName,
                displayName: modelName,
                provider: .custom
            ),
            details: [
                "endpoint=\(endpointText)",
                "model=\(modelName)",
                "api_key_source=\(apiKeySource.kind)",
                "api_key_ref=\(apiKeySource.reference)"
            ]
        )
    }

    public static func runnableSetupProofLines(
        for configuration: RomaWindowsAgentConfiguration
    ) throws -> [String] {
        guard configuration.usesWhisperCLI else {
            _ = try configuration.apiKeySource().resolve()
            return ["api_key_resolved=true"]
        }

        try requireExistingFile(try configuration.requireWhisperCLIPath(), option: "--whisper-cli")
        try requireExistingFile(try configuration.requireWhisperModelPath(), option: "--whisper-model")
        return [
            "whisper_cli_exists=true",
            "whisper_model_exists=true"
        ]
    }

    private static func requireExistingFile(_ path: String, option: String) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw RomaCommandLineOptionsError.invalidOptionValue(option)
        }
    }
}
