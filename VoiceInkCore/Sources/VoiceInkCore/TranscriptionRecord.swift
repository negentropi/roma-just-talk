import Foundation

public enum VoiceInkTranscriptionStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case completed
    case failed
    case canceled
}

public struct VoiceInkTranscriptionRecordFailurePlan: Equatable, Sendable {
    public let errorDescription: String
    public let status: VoiceInkTranscriptionStatus
    public let failedTranscriptText: String

    public init(errorDescription: String) {
        self.errorDescription = errorDescription
        self.status = .failed
        self.failedTranscriptText = VoiceInkTranscriptPresentation.failedTranscriptText(reason: errorDescription)
    }
}

public struct VoiceInkTranscriptionRecordCancellationPlan: Equatable, Sendable {
    public let text: String
    public let enhancedText: String?
    public let status: VoiceInkTranscriptionStatus
    public let duration: TimeInterval?
    public let transcriptionModelName: String?
    public let aiEnhancementModelName: String?
    public let promptName: String?
    public let transcriptionDuration: TimeInterval?
    public let enhancementDuration: TimeInterval?
    public let aiRequestSystemMessage: String?
    public let aiRequestUserMessage: String?
    public let transcriptionError: String?

    public init(
        duration: TimeInterval? = nil,
        modelName: String? = nil
    ) {
        self.text = VoiceInkTranscriptPresentation.canceledTranscriptionText
        self.enhancedText = nil
        self.status = .canceled
        self.duration = duration
        self.transcriptionModelName = modelName
        self.aiEnhancementModelName = nil
        self.promptName = nil
        self.transcriptionDuration = nil
        self.enhancementDuration = nil
        self.aiRequestSystemMessage = nil
        self.aiRequestUserMessage = nil
        self.transcriptionError = nil
    }
}

public struct VoiceInkRecordingTranscriptionDraft: Equatable, Sendable {
    public let text: String
    public let duration: TimeInterval
    public let audioFileURL: String?
    public let transcriptionModelName: String?
    public let powerModeName: String?
    public let powerModeEmoji: String?
    public let transcriptionStatus: VoiceInkTranscriptionStatus

    public init(
        text: String,
        duration: TimeInterval,
        audioFileURL: String?,
        transcriptionModelName: String? = nil,
        powerModeName: String? = nil,
        powerModeEmoji: String? = nil,
        transcriptionStatus: VoiceInkTranscriptionStatus
    ) {
        self.text = text
        self.duration = duration
        self.audioFileURL = audioFileURL
        self.transcriptionModelName = transcriptionModelName
        self.powerModeName = powerModeName
        self.powerModeEmoji = powerModeEmoji
        self.transcriptionStatus = transcriptionStatus
    }

    public static func pending(
        duration: TimeInterval,
        audioFileURL: String?,
        transcriptionModelName: String? = nil,
        powerModeName: String? = nil,
        powerModeEmoji: String? = nil
    ) -> VoiceInkRecordingTranscriptionDraft {
        VoiceInkRecordingTranscriptionDraft(
            text: "",
            duration: duration,
            audioFileURL: audioFileURL,
            transcriptionModelName: transcriptionModelName,
            powerModeName: powerModeName,
            powerModeEmoji: powerModeEmoji,
            transcriptionStatus: .pending
        )
    }

    public static func canceled(
        duration: TimeInterval,
        audioFileURL: String?,
        transcriptionModelName: String? = nil,
        powerModeName: String? = nil,
        powerModeEmoji: String? = nil
    ) -> VoiceInkRecordingTranscriptionDraft {
        VoiceInkRecordingTranscriptionDraft(
            text: VoiceInkTranscriptPresentation.canceledTranscriptionText,
            duration: duration,
            audioFileURL: audioFileURL,
            transcriptionModelName: transcriptionModelName,
            powerModeName: powerModeName,
            powerModeEmoji: powerModeEmoji,
            transcriptionStatus: .canceled
        )
    }
}

public enum VoiceInkEnhancementFailureDraftPolicy: Equatable, Sendable {
    case omitEnhancedText
    case storeFailureText
}

public struct VoiceInkAudioFileTranscriptionDraftContext: Equatable, Sendable {
    public let cleanedText: String
    public let duration: TimeInterval
    public let audioFileURL: String?
    public let transcriptionModelName: String?
    public let transcriptionDuration: TimeInterval?
    public let powerModeName: String?
    public let powerModeEmoji: String?

    public init(
        cleanedText: String,
        duration: TimeInterval,
        audioFileURL: String?,
        transcriptionModelName: String?,
        transcriptionDuration: TimeInterval?,
        powerModeName: String? = nil,
        powerModeEmoji: String? = nil
    ) {
        self.cleanedText = cleanedText
        self.duration = duration
        self.audioFileURL = audioFileURL
        self.transcriptionModelName = transcriptionModelName
        self.transcriptionDuration = transcriptionDuration
        self.powerModeName = powerModeName
        self.powerModeEmoji = powerModeEmoji
    }
}

public enum VoiceInkAudioFileTranscriptionEnhancementOutcome: Equatable, Sendable {
    case notAttempted
    case succeeded(VoiceInkAIEnhancementResult)
    case failed(reason: String, policy: VoiceInkEnhancementFailureDraftPolicy)
}

public struct VoiceInkAudioFileTranscriptionCompletionResult: Equatable, Sendable {
    public let draft: VoiceInkCompletedTranscriptionDraft
    public let enhancementFailureReason: String?

    public init(
        draft: VoiceInkCompletedTranscriptionDraft,
        enhancementFailureReason: String? = nil
    ) {
        self.draft = draft
        self.enhancementFailureReason = enhancementFailureReason
    }
}

public enum VoiceInkAudioFileTranscriptionDiagnostics {
    public static let wordReplacementsAppliedMessage = "✅ Word replacements applied"

    public static func permanentCopyFailedMessage(localizedDescription: String) -> String {
        "❌ Failed to create permanent copy of audio: \(localizedDescription)"
    }

    public static func transcriptionFailedMessage(localizedDescription: String) -> String {
        "❌ Transcription failed: \(localizedDescription)"
    }

    public static func saveFailedMessage(localizedDescription: String) -> String {
        "❌ Failed to save transcription: \(localizedDescription)"
    }
}

public enum VoiceInkAudioFileTranscriptionDraft {
    public static func completed(
        context: VoiceInkAudioFileTranscriptionDraftContext,
        enhancementOutcome: VoiceInkAudioFileTranscriptionEnhancementOutcome = .notAttempted
    ) -> VoiceInkCompletedTranscriptionDraft {
        switch enhancementOutcome {
        case .notAttempted:
            return VoiceInkCompletedTranscriptionDraft(
                cleanedText: context.cleanedText,
                duration: context.duration,
                audioFileURL: context.audioFileURL,
                transcriptionModelName: context.transcriptionModelName,
                transcriptionDuration: context.transcriptionDuration,
                powerModeName: context.powerModeName,
                powerModeEmoji: context.powerModeEmoji
            )
        case .succeeded(let enhancementResult):
            return VoiceInkCompletedTranscriptionDraft(
                cleanedText: context.cleanedText,
                duration: context.duration,
                audioFileURL: context.audioFileURL,
                transcriptionModelName: context.transcriptionModelName,
                transcriptionDuration: context.transcriptionDuration,
                powerModeName: context.powerModeName,
                powerModeEmoji: context.powerModeEmoji,
                enhancementResult: enhancementResult
            )
        case .failed(let reason, let policy):
            return VoiceInkCompletedTranscriptionDraft(
                cleanedText: context.cleanedText,
                duration: context.duration,
                audioFileURL: context.audioFileURL,
                transcriptionModelName: context.transcriptionModelName,
                transcriptionDuration: context.transcriptionDuration,
                powerModeName: context.powerModeName,
                powerModeEmoji: context.powerModeEmoji,
                enhancementFailureReason: reason,
                enhancementFailurePolicy: policy
            )
        }
    }

    public static func completionResult(
        context: VoiceInkAudioFileTranscriptionDraftContext,
        enhancementRequest: VoiceInkTranscriptionEnhancementRequest?,
        enhancementFailurePolicy: VoiceInkEnhancementFailureDraftPolicy,
        enhance: (VoiceInkTranscriptionEnhancementRequest) async throws -> VoiceInkAIEnhancementResult
    ) async -> VoiceInkAudioFileTranscriptionCompletionResult {
        guard let enhancementRequest else {
            return VoiceInkAudioFileTranscriptionCompletionResult(
                draft: completed(context: context)
            )
        }

        do {
            let enhancement = try await enhance(enhancementRequest)
            return VoiceInkAudioFileTranscriptionCompletionResult(
                draft: completed(
                    context: context,
                    enhancementOutcome: .succeeded(enhancement)
                )
            )
        } catch {
            let reason = VoiceInkErrorDescription.text(for: error)
            return VoiceInkAudioFileTranscriptionCompletionResult(
                draft: completed(
                    context: context,
                    enhancementOutcome: .failed(
                        reason: reason,
                        policy: enhancementFailurePolicy
                    )
                ),
                enhancementFailureReason: reason
            )
        }
    }
}

public struct VoiceInkCompletedTranscriptionDraft: Equatable, Sendable {
    public let text: String
    public let duration: TimeInterval
    public let enhancedText: String?
    public let audioFileURL: String?
    public let transcriptionModelName: String?
    public let aiEnhancementModelName: String?
    public let promptName: String?
    public let transcriptionDuration: TimeInterval?
    public let enhancementDuration: TimeInterval?
    public let aiRequestSystemMessage: String?
    public let aiRequestUserMessage: String?
    public let powerModeName: String?
    public let powerModeEmoji: String?
    public let transcriptionStatus: VoiceInkTranscriptionStatus

    public init(
        cleanedText: String,
        duration: TimeInterval,
        audioFileURL: String?,
        transcriptionModelName: String?,
        transcriptionDuration: TimeInterval?,
        powerModeName: String? = nil,
        powerModeEmoji: String? = nil,
        enhancementResult: VoiceInkAIEnhancementResult? = nil,
        enhancementFailureReason: String? = nil,
        enhancementFailurePolicy: VoiceInkEnhancementFailureDraftPolicy = .omitEnhancedText
    ) {
        self.text = cleanedText
        self.duration = duration
        self.audioFileURL = audioFileURL
        self.transcriptionModelName = transcriptionModelName
        self.transcriptionDuration = transcriptionDuration
        self.powerModeName = powerModeName
        self.powerModeEmoji = powerModeEmoji
        self.transcriptionStatus = .completed

        if let enhancementResult {
            self.enhancedText = enhancementResult.text
            self.aiEnhancementModelName = enhancementResult.modelName
            self.promptName = enhancementResult.promptName
            self.enhancementDuration = enhancementResult.duration
            self.aiRequestSystemMessage = enhancementResult.requestSystemMessage
            self.aiRequestUserMessage = enhancementResult.requestUserMessage
        } else {
            switch enhancementFailurePolicy {
            case .omitEnhancedText:
                self.enhancedText = nil
            case .storeFailureText:
                self.enhancedText = enhancementFailureReason.map {
                    VoiceInkPostProcessingFailurePresentation.enhancementFailureText(reason: $0)
                }
            }
            self.aiEnhancementModelName = nil
            self.promptName = nil
            self.enhancementDuration = nil
            self.aiRequestSystemMessage = nil
            self.aiRequestUserMessage = nil
        }
    }
}

public protocol VoiceInkMutableTranscriptionEnhancementRecord: AnyObject {
    var enhancedText: String? { get set }
    var aiEnhancementModelName: String? { get set }
    var enhancementDuration: TimeInterval? { get set }
}

public protocol VoiceInkMutableTranscriptionEnhancementMetadataRecord: VoiceInkMutableTranscriptionEnhancementRecord {
    var promptName: String? { get set }
    var aiRequestSystemMessage: String? { get set }
    var aiRequestUserMessage: String? { get set }
}

public protocol VoiceInkMutableTranscriptionRecord: VoiceInkMutableTranscriptionEnhancementRecord {
    var text: String { get set }
    var duration: TimeInterval { get set }
    var transcriptionModelName: String? { get set }
    var transcriptionDuration: TimeInterval? { get set }
    var transcriptionStatus: VoiceInkTranscriptionStatus { get set }
    var transcriptionError: String? { get set }
}

public extension VoiceInkMutableTranscriptionEnhancementRecord {
    func applyEnhancementResult(_ result: VoiceInkAIEnhancementResult) {
        enhancedText = result.text
        aiEnhancementModelName = result.modelName
        enhancementDuration = result.duration

        if let metadataRecord = self as? any VoiceInkMutableTranscriptionEnhancementMetadataRecord {
            metadataRecord.promptName = result.promptName
            metadataRecord.aiRequestSystemMessage = result.requestSystemMessage
            metadataRecord.aiRequestUserMessage = result.requestUserMessage
        }
    }

    func applyEnhancementFailure(
        reason: String,
        policy: VoiceInkEnhancementFailureDraftPolicy
    ) {
        switch policy {
        case .omitEnhancedText:
            enhancedText = nil
        case .storeFailureText:
            enhancedText = VoiceInkPostProcessingFailurePresentation.enhancementFailureText(
                reason: reason
            )
        }
        aiEnhancementModelName = nil
        enhancementDuration = nil

        if let metadataRecord = self as? any VoiceInkMutableTranscriptionEnhancementMetadataRecord {
            metadataRecord.promptName = nil
            metadataRecord.aiRequestSystemMessage = nil
            metadataRecord.aiRequestUserMessage = nil
        }
    }
}

public extension VoiceInkMutableTranscriptionRecord {
    func applyCompletedRunResult(_ result: VoiceInkTranscriptionRunResult) {
        text = result.cleanedText
        enhancedText = result.enhancedText
        transcriptionModelName = result.transcriptionModelName
        aiEnhancementModelName = result.aiEnhancementModelName
        transcriptionDuration = result.transcriptionDuration
        enhancementDuration = result.enhancementDuration
        transcriptionStatus = .completed
        transcriptionError = result.postProcessingError
    }

    func markTranscriptionFailed(_ errorDescription: String) {
        let plan = VoiceInkTranscriptionRecordFailurePlan(errorDescription: errorDescription)
        transcriptionStatus = plan.status
        transcriptionError = plan.errorDescription
    }

    func applyCancellationPlan(_ plan: VoiceInkTranscriptionRecordCancellationPlan) {
        text = plan.text
        enhancedText = plan.enhancedText
        if let duration = plan.duration {
            self.duration = duration
        }
        if let transcriptionModelName = plan.transcriptionModelName {
            self.transcriptionModelName = transcriptionModelName
        }
        aiEnhancementModelName = plan.aiEnhancementModelName
        transcriptionDuration = plan.transcriptionDuration
        enhancementDuration = plan.enhancementDuration
        transcriptionStatus = plan.status
        transcriptionError = plan.transcriptionError
    }

    func markTranscriptionCanceled(
        duration: TimeInterval? = nil,
        modelName: String? = nil
    ) {
        applyCancellationPlan(VoiceInkTranscriptionRecordCancellationPlan(
            duration: duration,
            modelName: modelName
        ))
    }
}

public extension VoiceInkMutableTranscriptionRecord where Self: VoiceInkStoredAudioRecord {
    @discardableResult
    func retranscribeStoredAudio(
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default,
        transcribe: (URL) async throws -> VoiceInkTranscriptionRunResult
    ) async throws -> String {
        guard let fileURL = existingAudioFileURL(relativeTo: recordingsDirectory, fileManager: fileManager) else {
            let error = VoiceInkEngineError.audioFileNotFound
            markTranscriptionFailed(VoiceInkErrorDescription.text(for: error))
            throw error
        }

        do {
            let result = try await transcribe(fileURL)
            applyCompletedRunResult(result)
            return result.finalText
        } catch {
            markTranscriptionFailed(VoiceInkErrorDescription.text(for: error))
            throw error
        }
    }
}

public enum VoiceInkStoredAudioRetranscriptionOutcome: Equatable, Sendable {
    case succeeded(String)
    case failed(reason: String)
}

public struct VoiceInkStoredAudioRetranscriptionRunner {
    public typealias RunSettingsProvider = () async -> VoiceInkTranscriptionRunSettings

    private let processor: VoiceInkTranscriptionRunProcessor
    private let runSettingsProvider: RunSettingsProvider
    private let apiKeyProvider: VoiceInkTranscriptionRunProcessor.APIKeyProvider
    private let transcriptionServiceProvider: VoiceInkTranscriptionRunProcessor.TranscriptionServiceProvider

    public init(
        processor: VoiceInkTranscriptionRunProcessor = VoiceInkTranscriptionRunProcessor(),
        runSettingsProvider: @escaping RunSettingsProvider,
        apiKeyProvider: @escaping VoiceInkTranscriptionRunProcessor.APIKeyProvider,
        transcriptionServiceProvider: @escaping VoiceInkTranscriptionRunProcessor.TranscriptionServiceProvider
    ) {
        self.processor = processor
        self.runSettingsProvider = runSettingsProvider
        self.apiKeyProvider = apiKeyProvider
        self.transcriptionServiceProvider = transcriptionServiceProvider
    }

    public func transcribe(fileURL: URL) async throws -> VoiceInkTranscriptionRunResult {
        let runSettings = await runSettingsProvider()
        return try await runSettings.transcribe(
            fileURL: fileURL,
            processor: processor,
            apiKeyProvider: apiKeyProvider,
            transcriptionServiceProvider: transcriptionServiceProvider
        )
    }

    @discardableResult
    public func retranscribe<Record: VoiceInkMutableTranscriptionRecord & VoiceInkStoredAudioRecord>(
        _ record: Record,
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) async throws -> String {
        try await record.retranscribeStoredAudio(
            relativeTo: recordingsDirectory,
            fileManager: fileManager
        ) { fileURL in
            try await transcribe(fileURL: fileURL)
        }
    }

    @discardableResult
    public func retranscribeWithOutcome<Record: VoiceInkMutableTranscriptionRecord & VoiceInkStoredAudioRecord>(
        _ record: Record,
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) async -> VoiceInkStoredAudioRetranscriptionOutcome {
        do {
            return .succeeded(try await retranscribe(
                record,
                relativeTo: recordingsDirectory,
                fileManager: fileManager
            ))
        } catch {
            return .failed(reason: VoiceInkErrorDescription.text(for: error))
        }
    }
}

public enum VoiceInkStoredAudioRetranscription {
    public typealias RunSettingsProvider = VoiceInkStoredAudioRetranscriptionRunner.RunSettingsProvider
    public typealias IOSAppSettingsRunSnapshotProvider = () async -> VoiceInkIOSAppSettingsRunSnapshot
    public typealias LocalWhisperServiceFactory = VoiceInkAudioTranscriptionServiceFactory.LocalWhisperServiceFactory
    typealias RemoteServiceFactory = VoiceInkAudioTranscriptionServiceFactory.RemoteServiceFactory

    @discardableResult
    public static func retranscribe<Record: VoiceInkMutableTranscriptionRecord & VoiceInkStoredAudioRecord>(
        _ record: Record,
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default,
        runSettingsProvider: @escaping RunSettingsProvider,
        apiKeyProvider: @escaping VoiceInkTranscriptionRunProcessor.APIKeyProvider,
        localWhisperServiceFactory: @escaping LocalWhisperServiceFactory
    ) async throws -> String {
        try await retranscribe(
            record,
            relativeTo: recordingsDirectory,
            fileManager: fileManager,
            processor: VoiceInkTranscriptionRunProcessor(),
            runSettingsProvider: runSettingsProvider,
            apiKeyProvider: apiKeyProvider,
            localWhisperServiceFactory: localWhisperServiceFactory,
            remoteServiceFactory: { VoiceInkRemoteTranscriptionService(provider: $0) }
        )
    }

    @discardableResult
    public static func retranscribeWithOutcome<Record: VoiceInkMutableTranscriptionRecord & VoiceInkStoredAudioRecord>(
        _ record: Record,
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default,
        runSettingsProvider: @escaping RunSettingsProvider,
        apiKeyProvider: @escaping VoiceInkTranscriptionRunProcessor.APIKeyProvider,
        localWhisperServiceFactory: @escaping LocalWhisperServiceFactory
    ) async -> VoiceInkStoredAudioRetranscriptionOutcome {
        await retranscribeWithOutcome(
            record,
            relativeTo: recordingsDirectory,
            fileManager: fileManager,
            processor: VoiceInkTranscriptionRunProcessor(),
            runSettingsProvider: runSettingsProvider,
            apiKeyProvider: apiKeyProvider,
            localWhisperServiceFactory: localWhisperServiceFactory,
            remoteServiceFactory: { VoiceInkRemoteTranscriptionService(provider: $0) }
        )
    }

    @discardableResult
    public static func retranscribeWithOutcome<Record: VoiceInkMutableTranscriptionRecord & VoiceInkStoredAudioRecord>(
        _ record: Record,
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        iOSAppSettingsRunSnapshotProvider: @escaping IOSAppSettingsRunSnapshotProvider,
        apiKeyProvider: @escaping VoiceInkTranscriptionRunProcessor.APIKeyProvider,
        localWhisperServiceFactory: @escaping LocalWhisperServiceFactory
    ) async -> VoiceInkStoredAudioRetranscriptionOutcome {
        await retranscribeWithOutcome(
            record,
            relativeTo: recordingsDirectory,
            fileManager: fileManager,
            processor: VoiceInkTranscriptionRunProcessor(),
            defaults: defaults,
            iOSAppSettingsRunSnapshotProvider: iOSAppSettingsRunSnapshotProvider,
            apiKeyProvider: apiKeyProvider,
            localWhisperServiceFactory: localWhisperServiceFactory,
            remoteServiceFactory: { VoiceInkRemoteTranscriptionService(provider: $0) }
        )
    }

    @discardableResult
    static func retranscribe<Record: VoiceInkMutableTranscriptionRecord & VoiceInkStoredAudioRecord>(
        _ record: Record,
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default,
        processor: VoiceInkTranscriptionRunProcessor = VoiceInkTranscriptionRunProcessor(),
        runSettingsProvider: @escaping RunSettingsProvider,
        apiKeyProvider: @escaping VoiceInkTranscriptionRunProcessor.APIKeyProvider,
        localWhisperServiceFactory: @escaping LocalWhisperServiceFactory,
        remoteServiceFactory: @escaping RemoteServiceFactory = { VoiceInkRemoteTranscriptionService(provider: $0) }
    ) async throws -> String {
        try await runner(
            processor: processor,
            runSettingsProvider: runSettingsProvider,
            apiKeyProvider: apiKeyProvider,
            localWhisperServiceFactory: localWhisperServiceFactory,
            remoteServiceFactory: remoteServiceFactory
        ).retranscribe(
            record,
            relativeTo: recordingsDirectory,
            fileManager: fileManager
        )
    }

    @discardableResult
    static func retranscribeWithOutcome<Record: VoiceInkMutableTranscriptionRecord & VoiceInkStoredAudioRecord>(
        _ record: Record,
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default,
        processor: VoiceInkTranscriptionRunProcessor = VoiceInkTranscriptionRunProcessor(),
        defaults: UserDefaults = .standard,
        iOSAppSettingsRunSnapshotProvider: @escaping IOSAppSettingsRunSnapshotProvider,
        apiKeyProvider: @escaping VoiceInkTranscriptionRunProcessor.APIKeyProvider,
        localWhisperServiceFactory: @escaping LocalWhisperServiceFactory,
        remoteServiceFactory: @escaping RemoteServiceFactory = { VoiceInkRemoteTranscriptionService(provider: $0) }
    ) async -> VoiceInkStoredAudioRetranscriptionOutcome {
        await retranscribeWithOutcome(
            record,
            relativeTo: recordingsDirectory,
            fileManager: fileManager,
            processor: processor,
            runSettingsProvider: {
                let snapshot = await iOSAppSettingsRunSnapshotProvider()
                return snapshot.transcriptionRunSettings(defaults: defaults)
            },
            apiKeyProvider: apiKeyProvider,
            localWhisperServiceFactory: localWhisperServiceFactory,
            remoteServiceFactory: remoteServiceFactory
        )
    }

    @discardableResult
    static func retranscribeWithOutcome<Record: VoiceInkMutableTranscriptionRecord & VoiceInkStoredAudioRecord>(
        _ record: Record,
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default,
        processor: VoiceInkTranscriptionRunProcessor = VoiceInkTranscriptionRunProcessor(),
        runSettingsProvider: @escaping RunSettingsProvider,
        apiKeyProvider: @escaping VoiceInkTranscriptionRunProcessor.APIKeyProvider,
        localWhisperServiceFactory: @escaping LocalWhisperServiceFactory,
        remoteServiceFactory: @escaping RemoteServiceFactory = { VoiceInkRemoteTranscriptionService(provider: $0) }
    ) async -> VoiceInkStoredAudioRetranscriptionOutcome {
        await runner(
            processor: processor,
            runSettingsProvider: runSettingsProvider,
            apiKeyProvider: apiKeyProvider,
            localWhisperServiceFactory: localWhisperServiceFactory,
            remoteServiceFactory: remoteServiceFactory
        ).retranscribeWithOutcome(
            record,
            relativeTo: recordingsDirectory,
            fileManager: fileManager
        )
    }

    private static func runner(
        processor: VoiceInkTranscriptionRunProcessor = VoiceInkTranscriptionRunProcessor(),
        runSettingsProvider: @escaping RunSettingsProvider,
        apiKeyProvider: @escaping VoiceInkTranscriptionRunProcessor.APIKeyProvider,
        localWhisperServiceFactory: @escaping LocalWhisperServiceFactory,
        remoteServiceFactory: @escaping RemoteServiceFactory = { VoiceInkRemoteTranscriptionService(provider: $0) }
    ) -> VoiceInkStoredAudioRetranscriptionRunner {
        let serviceFactory = VoiceInkAudioTranscriptionServiceFactory(
            localWhisperServiceFactory: localWhisperServiceFactory,
            remoteServiceFactory: remoteServiceFactory
        )

        return VoiceInkStoredAudioRetranscriptionRunner(
            processor: processor,
            runSettingsProvider: runSettingsProvider,
            apiKeyProvider: apiKeyProvider,
            transcriptionServiceProvider: { provider in
                serviceFactory.service(for: provider)
            }
        )
    }
}
