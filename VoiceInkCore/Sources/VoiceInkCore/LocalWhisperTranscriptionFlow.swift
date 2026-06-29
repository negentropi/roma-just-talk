import Foundation

public enum VoiceInkLocalWhisperTranscriptionDiagnostics {
    public static let macOSAudioSamplesProcessingFailedMessage = "❌ Failed to process audio samples for local Whisper transcription."
    public static let macOSCoreTranscriptionFailedMessage = "❌ Core transcription engine failed (whisper_full)."
    public static let macOSTranscriptionCompletedMessage = "Whisper transcription completed successfully."
    public static let iOSStartingLocalTranscriptionMessage = "Starting local transcription."
    public static let iOSAudioProcessingFailedMessage = "Audio processing failed."
    public static let iOSTranscriptionFailedMessage = "Transcription failed."
    public static let iOSContextResourcesReleasedMessage = "Whisper context resources released."
    public static let iOSTranscriptionCompletedMessage = "Transcription completed successfully."

    public static func macOSInitiatingLocalTranscriptionMessage(modelDisplayName: String) -> String {
        "Initiating local transcription for model: \(modelDisplayName)"
    }

    public static func macOSUsingLoadedModelMessage(modelName: String) -> String {
        "Using already loaded model: \(modelName)"
    }

    public static func macOSModelFileNotFoundMessage(modelName: String) -> String {
        "❌ Model file not found for: \(modelName)"
    }

    public static func macOSLoadingModelMessage(modelName: String) -> String {
        "Loading model: \(modelName)"
    }

    public static func macOSModelLoadFailedMessage(modelName: String, localizedDescription: String) -> String {
        "❌ Failed to load model: \(modelName) - \(localizedDescription)"
    }

    public static func iOSUsingModelMessage(modelPath: String) -> String {
        "Using model at \(modelPath)"
    }

    public static func iOSProcessedAudioSamplesMessage(count: Int) -> String {
        "Processed \(count) audio samples."
    }

    public static func iOSAudioProcessingFailedMessage(localizedDescription: String) -> String {
        "Audio processing failed: \(localizedDescription)"
    }
}

public struct VoiceInkLocalWhisperContextPlan<Context> {
    public let context: Context
    public let shouldReleaseContext: Bool
    public let shouldReleaseContextOnFailure: Bool

    public init(
        context: Context,
        shouldReleaseContext: Bool,
        shouldReleaseContextOnFailure: Bool? = nil
    ) {
        self.context = context
        self.shouldReleaseContext = shouldReleaseContext
        self.shouldReleaseContextOnFailure = shouldReleaseContextOnFailure ?? shouldReleaseContext
    }
}

public struct VoiceInkLocalWhisperTranscriptionRequest: Equatable, Sendable {
    public let audioURL: URL
    public let language: String?
    public let prompt: String?
    public let failurePlatform: VoiceInkLocalWhisperPlatform
    public let mapsThrownAudioSampleErrors: Bool

    public init(
        audioURL: URL,
        language: String? = nil,
        prompt: String? = nil,
        failurePlatform: VoiceInkLocalWhisperPlatform,
        mapsThrownAudioSampleErrors: Bool = true
    ) {
        self.audioURL = audioURL
        self.language = language
        self.prompt = prompt
        self.failurePlatform = failurePlatform
        self.mapsThrownAudioSampleErrors = mapsThrownAudioSampleErrors
    }

    public static func macOS(
        audioURL: URL,
        defaults: UserDefaults = .standard
    ) -> VoiceInkLocalWhisperTranscriptionRequest {
        VoiceInkLocalWhisperTranscriptionRequest(
            audioURL: audioURL,
            language: VoiceInkTranscriptionLanguagePreference.selectedLanguage(from: defaults),
            prompt: VoiceInkTranscriptionPromptPreference.localWhisperPromptForSelectedLanguage(from: defaults),
            failurePlatform: .macOS,
            mapsThrownAudioSampleErrors: false
        )
    }

    public static func iOS(
        audioURL: URL,
        language: String? = nil,
        prompt: String? = nil
    ) -> VoiceInkLocalWhisperTranscriptionRequest {
        VoiceInkLocalWhisperTranscriptionRequest(
            audioURL: audioURL,
            language: language,
            prompt: prompt ?? "",
            failurePlatform: .iOS
        )
    }
}

public struct VoiceInkLocalWhisperTranscriptionActions<Context> {
    public let resolveContext: () async throws -> VoiceInkLocalWhisperContextPlan<Context>
    public let readAudioSamples: (URL) throws -> [Float]?
    public let runTranscription: (Context, [Float], String?, String?) async -> Bool
    public let transcriptionText: (Context) async -> String
    public let releaseContext: (Context) async -> Void

    public init(
        resolveContext: @escaping () async throws -> VoiceInkLocalWhisperContextPlan<Context>,
        readAudioSamples: @escaping (URL) throws -> [Float]?,
        runTranscription: @escaping (Context, [Float], String?, String?) async -> Bool,
        transcriptionText: @escaping (Context) async -> String,
        releaseContext: @escaping (Context) async -> Void
    ) {
        self.resolveContext = resolveContext
        self.readAudioSamples = readAudioSamples
        self.runTranscription = runTranscription
        self.transcriptionText = transcriptionText
        self.releaseContext = releaseContext
    }
}

public enum VoiceInkLocalWhisperTranscriptionFlow {
    public static func transcribe<Context>(
        request: VoiceInkLocalWhisperTranscriptionRequest,
        actions: VoiceInkLocalWhisperTranscriptionActions<Context>
    ) async throws -> String {
        let contextPlan = try await actions.resolveContext()

        do {
            let samples = try readSamples(
                request: request,
                actions: actions
            )

            let success = await actions.runTranscription(
                contextPlan.context,
                samples,
                request.language,
                request.prompt
            )
            guard success else {
                throw VoiceInkLocalWhisperFailurePolicy.error(
                    for: .transcriptionFailed,
                    platform: request.failurePlatform
                )
            }

            let text = await actions.transcriptionText(contextPlan.context)
            await releaseIfNeeded(contextPlan, afterFailure: false, actions: actions)
            return text
        } catch {
            await releaseIfNeeded(contextPlan, afterFailure: true, actions: actions)
            throw error
        }
    }

    private static func readSamples<Context>(
        request: VoiceInkLocalWhisperTranscriptionRequest,
        actions: VoiceInkLocalWhisperTranscriptionActions<Context>
    ) throws -> [Float] {
        do {
            guard let samples = try actions.readAudioSamples(request.audioURL) else {
                throw VoiceInkLocalWhisperFailurePolicy.error(
                    for: .audioProcessingFailed,
                    platform: request.failurePlatform
                )
            }
            return samples
        } catch let error as VoiceInkEngineError {
            throw error
        } catch {
            guard request.mapsThrownAudioSampleErrors else { throw error }
            throw VoiceInkLocalWhisperFailurePolicy.error(
                for: .audioProcessingFailed,
                platform: request.failurePlatform
            )
        }
    }

    private static func releaseIfNeeded<Context>(
        _ contextPlan: VoiceInkLocalWhisperContextPlan<Context>,
        afterFailure: Bool,
        actions: VoiceInkLocalWhisperTranscriptionActions<Context>
    ) async {
        guard contextPlan.shouldReleaseContext else { return }
        guard !afterFailure || contextPlan.shouldReleaseContextOnFailure else { return }
        await actions.releaseContext(contextPlan.context)
    }
}
