import Foundation

public enum RomaTranscriptionStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case completed
    case failed
    case canceled
}

public struct RomaTranscriptionRecordFailurePlan: Equatable, Sendable {
    public let errorDescription: String
    public let status: RomaTranscriptionStatus
    public let failedTranscriptText: String

    public init(errorDescription: String) {
        self.errorDescription = errorDescription
        self.status = .failed
        self.failedTranscriptText = RomaTranscriptPresentation.failedTranscriptText(reason: errorDescription)
    }
}

public struct RomaTranscriptionRecordCancellationPlan: Equatable, Sendable {
    public let text: String
    public let enhancedText: String?
    public let status: RomaTranscriptionStatus
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
        self.text = RomaTranscriptPresentation.canceledTranscriptionText
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

public struct RomaRecordingTranscriptionDraft: Equatable, Sendable {
    public let text: String
    public let duration: TimeInterval
    public let audioFileURL: String?
    public let transcriptionModelName: String?
    public let powerModeName: String?
    public let powerModeEmoji: String?
    public let transcriptionStatus: RomaTranscriptionStatus

    public init(
        text: String,
        duration: TimeInterval,
        audioFileURL: String?,
        transcriptionModelName: String? = nil,
        powerModeName: String? = nil,
        powerModeEmoji: String? = nil,
        transcriptionStatus: RomaTranscriptionStatus
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
    ) -> RomaRecordingTranscriptionDraft {
        RomaRecordingTranscriptionDraft(
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
    ) -> RomaRecordingTranscriptionDraft {
        RomaRecordingTranscriptionDraft(
            text: RomaTranscriptPresentation.canceledTranscriptionText,
            duration: duration,
            audioFileURL: audioFileURL,
            transcriptionModelName: transcriptionModelName,
            powerModeName: powerModeName,
            powerModeEmoji: powerModeEmoji,
            transcriptionStatus: .canceled
        )
    }
}

public enum RomaEnhancementFailureDraftPolicy: Equatable, Sendable {
    case omitEnhancedText
    case storeFailureText
}

public struct RomaAudioFileTranscriptionDraftContext: Equatable, Sendable {
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

public enum RomaAudioFileTranscriptionEnhancementOutcome: Equatable, Sendable {
    case notAttempted
    case succeeded(RomaAIEnhancementResult)
    case failed(reason: String, policy: RomaEnhancementFailureDraftPolicy)
}

public struct RomaAudioFileTranscriptionCompletionResult: Equatable, Sendable {
    public let draft: RomaCompletedTranscriptionDraft
    public let enhancementFailureReason: String?

    public init(
        draft: RomaCompletedTranscriptionDraft,
        enhancementFailureReason: String? = nil
    ) {
        self.draft = draft
        self.enhancementFailureReason = enhancementFailureReason
    }
}

public enum RomaAudioFileTranscriptionDiagnostics {
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

public enum RomaAudioFileTranscriptionDraft {
    public static func completed(
        context: RomaAudioFileTranscriptionDraftContext,
        enhancementOutcome: RomaAudioFileTranscriptionEnhancementOutcome = .notAttempted
    ) -> RomaCompletedTranscriptionDraft {
        switch enhancementOutcome {
        case .notAttempted:
            return RomaCompletedTranscriptionDraft(
                cleanedText: context.cleanedText,
                duration: context.duration,
                audioFileURL: context.audioFileURL,
                transcriptionModelName: context.transcriptionModelName,
                transcriptionDuration: context.transcriptionDuration,
                powerModeName: context.powerModeName,
                powerModeEmoji: context.powerModeEmoji
            )
        case .succeeded(let enhancementResult):
            return RomaCompletedTranscriptionDraft(
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
            return RomaCompletedTranscriptionDraft(
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
        context: RomaAudioFileTranscriptionDraftContext,
        enhancementRequest: RomaTranscriptionEnhancementRequest?,
        enhancementFailurePolicy: RomaEnhancementFailureDraftPolicy,
        enhance: (RomaTranscriptionEnhancementRequest) async throws -> RomaAIEnhancementResult
    ) async -> RomaAudioFileTranscriptionCompletionResult {
        guard let enhancementRequest else {
            return RomaAudioFileTranscriptionCompletionResult(
                draft: completed(context: context)
            )
        }

        do {
            let enhancement = try await enhance(enhancementRequest)
            return RomaAudioFileTranscriptionCompletionResult(
                draft: completed(
                    context: context,
                    enhancementOutcome: .succeeded(enhancement)
                )
            )
        } catch {
            let reason = RomaErrorDescription.text(for: error)
            return RomaAudioFileTranscriptionCompletionResult(
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

public struct RomaCompletedTranscriptionDraft: Equatable, Sendable {
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
    public let transcriptionStatus: RomaTranscriptionStatus

    public init(
        cleanedText: String,
        duration: TimeInterval,
        audioFileURL: String?,
        transcriptionModelName: String?,
        transcriptionDuration: TimeInterval?,
        powerModeName: String? = nil,
        powerModeEmoji: String? = nil,
        enhancementResult: RomaAIEnhancementResult? = nil,
        enhancementFailureReason: String? = nil,
        enhancementFailurePolicy: RomaEnhancementFailureDraftPolicy = .omitEnhancedText
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
                    RomaPostProcessingFailurePresentation.enhancementFailureText(reason: $0)
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

public protocol RomaMutableTranscriptionEnhancementRecord: AnyObject {
    var enhancedText: String? { get set }
    var aiEnhancementModelName: String? { get set }
    var enhancementDuration: TimeInterval? { get set }
}

public protocol RomaMutableTranscriptionEnhancementMetadataRecord: RomaMutableTranscriptionEnhancementRecord {
    var promptName: String? { get set }
    var aiRequestSystemMessage: String? { get set }
    var aiRequestUserMessage: String? { get set }
}

public protocol RomaMutableTranscriptionRecord: RomaMutableTranscriptionEnhancementRecord {
    var text: String { get set }
    var duration: TimeInterval { get set }
    var transcriptionModelName: String? { get set }
    var transcriptionDuration: TimeInterval? { get set }
    var transcriptionStatus: RomaTranscriptionStatus { get set }
    var transcriptionError: String? { get set }
}

public extension RomaMutableTranscriptionEnhancementRecord {
    func applyEnhancementResult(_ result: RomaAIEnhancementResult) {
        enhancedText = result.text
        aiEnhancementModelName = result.modelName
        enhancementDuration = result.duration

        if let metadataRecord = self as? any RomaMutableTranscriptionEnhancementMetadataRecord {
            metadataRecord.promptName = result.promptName
            metadataRecord.aiRequestSystemMessage = result.requestSystemMessage
            metadataRecord.aiRequestUserMessage = result.requestUserMessage
        }
    }

    func applyEnhancementFailure(
        reason: String,
        policy: RomaEnhancementFailureDraftPolicy
    ) {
        switch policy {
        case .omitEnhancedText:
            enhancedText = nil
        case .storeFailureText:
            enhancedText = RomaPostProcessingFailurePresentation.enhancementFailureText(
                reason: reason
            )
        }
        aiEnhancementModelName = nil
        enhancementDuration = nil

        if let metadataRecord = self as? any RomaMutableTranscriptionEnhancementMetadataRecord {
            metadataRecord.promptName = nil
            metadataRecord.aiRequestSystemMessage = nil
            metadataRecord.aiRequestUserMessage = nil
        }
    }
}

public enum RomaStoredTranscriptionReEnhancementOutcome: Equatable, Sendable {
    case succeeded(String)
    case failed(reason: String)
    case canceled
}

public enum RomaStoredTranscriptionReEnhancement {
    public static func run<Record: RomaMutableTranscriptionEnhancementRecord>(
        _ record: Record,
        rawText: String,
        runSettings: RomaTranscriptionRunSettings,
        processor: RomaTranscriptionRunProcessor = RomaTranscriptionRunProcessor(),
        apiKeyProvider: RomaTranscriptionRunProcessor.APIKeyProvider
    ) async -> RomaStoredTranscriptionReEnhancementOutcome {
        guard runSettings.configuration.isPostProcessingEnabled else {
            return .failed(
                reason: RomaPostProcessingFailurePresentation.enhancementUnavailableFallbackText
            )
        }

        do {
            let result = try await runSettings.processTranscribedText(
                rawText,
                forcePostProcessing: true,
                processor: processor,
                apiKeyProvider: apiKeyProvider
            )
            guard let enhancement = result.postProcessingResult else {
                return .failed(
                    reason: result.postProcessingError
                        ?? RomaPostProcessingFailurePresentation.enhancementUnavailableFallbackText
                )
            }

            record.applyEnhancementResult(enhancement)
            return .succeeded(enhancement.text)
        } catch is CancellationError {
            return .canceled
        } catch {
            return .failed(reason: RomaErrorDescription.text(for: error))
        }
    }
}

public extension RomaMutableTranscriptionRecord {
    func applyCompletedRunResult(_ result: RomaTranscriptionRunResult) {
        text = result.cleanedText
        enhancedText = result.enhancedText
        transcriptionModelName = result.transcriptionModelName
        aiEnhancementModelName = result.aiEnhancementModelName
        transcriptionDuration = result.transcriptionDuration
        enhancementDuration = result.enhancementDuration
        transcriptionStatus = .completed
        transcriptionError = result.postProcessingError

        if let enhancement = result.postProcessingResult {
            applyEnhancementResult(enhancement)
        } else if let metadataRecord = self as? any RomaMutableTranscriptionEnhancementMetadataRecord {
            metadataRecord.promptName = nil
            metadataRecord.aiRequestSystemMessage = nil
            metadataRecord.aiRequestUserMessage = nil
        }
    }

    func markTranscriptionFailed(_ errorDescription: String) {
        let plan = RomaTranscriptionRecordFailurePlan(errorDescription: errorDescription)
        transcriptionStatus = plan.status
        transcriptionError = plan.errorDescription
    }

    func applyCancellationPlan(_ plan: RomaTranscriptionRecordCancellationPlan) {
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
        applyCancellationPlan(RomaTranscriptionRecordCancellationPlan(
            duration: duration,
            modelName: modelName
        ))
    }
}

public extension RomaMutableTranscriptionRecord where Self: RomaStoredAudioRecord {
    @discardableResult
    func retranscribeStoredAudio(
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default,
        transcribe: (URL) async throws -> RomaTranscriptionRunResult
    ) async throws -> String {
        try Task.checkCancellation()

        guard let fileURL = existingAudioFileURL(relativeTo: recordingsDirectory, fileManager: fileManager) else {
            let error = RomaEngineError.audioFileNotFound
            markTranscriptionFailed(RomaErrorDescription.text(for: error))
            throw error
        }

        do {
            let result = try await transcribe(fileURL)
            try Task.checkCancellation()
            applyCompletedRunResult(result)
            return result.finalText
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            markTranscriptionFailed(RomaErrorDescription.text(for: error))
            throw error
        }
    }
}

public enum RomaStoredAudioRetranscriptionOutcome: Equatable, Sendable {
    case succeeded(String)
    case failed(reason: String)
    case canceled
}

public struct RomaStoredAudioRetranscriptionRunner {
    public typealias RunSettingsProvider = () async -> RomaTranscriptionRunSettings

    private let processor: RomaTranscriptionRunProcessor
    private let runSettingsProvider: RunSettingsProvider
    private let apiKeyProvider: RomaTranscriptionRunProcessor.APIKeyProvider
    private let transcriptionServiceProvider: RomaTranscriptionRunProcessor.TranscriptionServiceProvider

    public init(
        processor: RomaTranscriptionRunProcessor = RomaTranscriptionRunProcessor(),
        runSettingsProvider: @escaping RunSettingsProvider,
        apiKeyProvider: @escaping RomaTranscriptionRunProcessor.APIKeyProvider,
        transcriptionServiceProvider: @escaping RomaTranscriptionRunProcessor.TranscriptionServiceProvider
    ) {
        self.processor = processor
        self.runSettingsProvider = runSettingsProvider
        self.apiKeyProvider = apiKeyProvider
        self.transcriptionServiceProvider = transcriptionServiceProvider
    }

    public func transcribe(fileURL: URL) async throws -> RomaTranscriptionRunResult {
        let runSettings = await runSettingsProvider()
        return try await runSettings.transcribe(
            fileURL: fileURL,
            processor: processor,
            apiKeyProvider: apiKeyProvider,
            transcriptionServiceProvider: transcriptionServiceProvider
        )
    }

    @discardableResult
    public func retranscribe<Record: RomaMutableTranscriptionRecord & RomaStoredAudioRecord>(
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
    public func retranscribeWithOutcome<Record: RomaMutableTranscriptionRecord & RomaStoredAudioRecord>(
        _ record: Record,
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) async -> RomaStoredAudioRetranscriptionOutcome {
        do {
            return .succeeded(try await retranscribe(
                record,
                relativeTo: recordingsDirectory,
                fileManager: fileManager
            ))
        } catch is CancellationError {
            return .canceled
        } catch {
            return .failed(reason: RomaErrorDescription.text(for: error))
        }
    }
}

public enum RomaStoredAudioRetranscription {
    public typealias RunSettingsProvider = RomaStoredAudioRetranscriptionRunner.RunSettingsProvider
    public typealias IOSAppSettingsRunSnapshotProvider = () async -> RomaIOSAppSettingsRunSnapshot
    public typealias LocalWhisperServiceFactory = RomaAudioTranscriptionServiceFactory.LocalWhisperServiceFactory
    public typealias LocalFluidAudioServiceFactory = RomaAudioTranscriptionServiceFactory.LocalFluidAudioServiceFactory
    public typealias NativeAppleServiceFactory = RomaAudioTranscriptionServiceFactory.NativeAppleServiceFactory
    public typealias CustomCloudServiceFactory = RomaAudioTranscriptionServiceFactory.CustomCloudServiceFactory
    typealias RemoteServiceFactory = RomaAudioTranscriptionServiceFactory.RemoteServiceFactory

    @discardableResult
    public static func retranscribe<Record: RomaMutableTranscriptionRecord & RomaStoredAudioRecord>(
        _ record: Record,
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default,
        runSettingsProvider: @escaping RunSettingsProvider,
        apiKeyProvider: @escaping RomaTranscriptionRunProcessor.APIKeyProvider,
        localWhisperServiceFactory: @escaping LocalWhisperServiceFactory
    ) async throws -> String {
        try await retranscribe(
            record,
            relativeTo: recordingsDirectory,
            fileManager: fileManager,
            processor: RomaTranscriptionRunProcessor(),
            runSettingsProvider: runSettingsProvider,
            apiKeyProvider: apiKeyProvider,
            localWhisperServiceFactory: localWhisperServiceFactory,
            remoteServiceFactory: { RomaRemoteTranscriptionService(provider: $0) }
        )
    }

    @discardableResult
    public static func retranscribeWithOutcome<Record: RomaMutableTranscriptionRecord & RomaStoredAudioRecord>(
        _ record: Record,
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default,
        runSettingsProvider: @escaping RunSettingsProvider,
        apiKeyProvider: @escaping RomaTranscriptionRunProcessor.APIKeyProvider,
        localWhisperServiceFactory: @escaping LocalWhisperServiceFactory
    ) async -> RomaStoredAudioRetranscriptionOutcome {
        await retranscribeWithOutcome(
            record,
            relativeTo: recordingsDirectory,
            fileManager: fileManager,
            processor: RomaTranscriptionRunProcessor(),
            runSettingsProvider: runSettingsProvider,
            apiKeyProvider: apiKeyProvider,
            localWhisperServiceFactory: localWhisperServiceFactory,
            remoteServiceFactory: { RomaRemoteTranscriptionService(provider: $0) }
        )
    }

    @discardableResult
    public static func retranscribeWithOutcome<Record: RomaMutableTranscriptionRecord & RomaStoredAudioRecord>(
        _ record: Record,
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default,
        runSettings: RomaTranscriptionRunSettings,
        apiKeyProvider: @escaping RomaTranscriptionRunProcessor.APIKeyProvider,
        localWhisperServiceFactory: @escaping LocalWhisperServiceFactory,
        localFluidAudioServiceFactory: @escaping LocalFluidAudioServiceFactory = {
            RomaUnsupportedAudioTranscriptionService()
        },
        nativeAppleServiceFactory: @escaping NativeAppleServiceFactory = {
            RomaUnsupportedAudioTranscriptionService()
        },
        customCloudServiceFactory: @escaping CustomCloudServiceFactory = {
            RomaUnsupportedAudioTranscriptionService()
        }
    ) async -> RomaStoredAudioRetranscriptionOutcome {
        await retranscribeWithOutcome(
            record,
            relativeTo: recordingsDirectory,
            fileManager: fileManager,
            runSettingsProvider: { runSettings },
            apiKeyProvider: apiKeyProvider,
            localWhisperServiceFactory: localWhisperServiceFactory,
            localFluidAudioServiceFactory: localFluidAudioServiceFactory,
            nativeAppleServiceFactory: nativeAppleServiceFactory,
            customCloudServiceFactory: customCloudServiceFactory
        )
    }

    @discardableResult
    public static func retranscribeWithOutcome<Record: RomaMutableTranscriptionRecord & RomaStoredAudioRecord>(
        _ record: Record,
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        iOSAppSettingsRunSnapshotProvider: @escaping IOSAppSettingsRunSnapshotProvider,
        apiKeyProvider: @escaping RomaTranscriptionRunProcessor.APIKeyProvider,
        localWhisperServiceFactory: @escaping LocalWhisperServiceFactory,
        localFluidAudioServiceFactory: @escaping LocalFluidAudioServiceFactory = {
            RomaUnsupportedAudioTranscriptionService()
        },
        nativeAppleServiceFactory: @escaping NativeAppleServiceFactory = {
            RomaUnsupportedAudioTranscriptionService()
        },
        customCloudServiceFactory: @escaping CustomCloudServiceFactory = {
            RomaUnsupportedAudioTranscriptionService()
        }
    ) async -> RomaStoredAudioRetranscriptionOutcome {
        await retranscribeWithOutcome(
            record,
            relativeTo: recordingsDirectory,
            fileManager: fileManager,
            processor: RomaTranscriptionRunProcessor(),
            defaults: defaults,
            iOSAppSettingsRunSnapshotProvider: iOSAppSettingsRunSnapshotProvider,
            apiKeyProvider: apiKeyProvider,
            localWhisperServiceFactory: localWhisperServiceFactory,
            localFluidAudioServiceFactory: localFluidAudioServiceFactory,
            nativeAppleServiceFactory: nativeAppleServiceFactory,
            customCloudServiceFactory: customCloudServiceFactory,
            remoteServiceFactory: { RomaRemoteTranscriptionService(provider: $0) }
        )
    }

    @discardableResult
    static func retranscribe<Record: RomaMutableTranscriptionRecord & RomaStoredAudioRecord>(
        _ record: Record,
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default,
        processor: RomaTranscriptionRunProcessor = RomaTranscriptionRunProcessor(),
        runSettingsProvider: @escaping RunSettingsProvider,
        apiKeyProvider: @escaping RomaTranscriptionRunProcessor.APIKeyProvider,
        localWhisperServiceFactory: @escaping LocalWhisperServiceFactory,
        localFluidAudioServiceFactory: @escaping LocalFluidAudioServiceFactory = {
            RomaUnsupportedAudioTranscriptionService()
        },
        nativeAppleServiceFactory: @escaping NativeAppleServiceFactory = {
            RomaUnsupportedAudioTranscriptionService()
        },
        customCloudServiceFactory: @escaping CustomCloudServiceFactory = {
            RomaUnsupportedAudioTranscriptionService()
        },
        remoteServiceFactory: @escaping RemoteServiceFactory = { RomaRemoteTranscriptionService(provider: $0) }
    ) async throws -> String {
        try await runner(
            processor: processor,
            runSettingsProvider: runSettingsProvider,
            apiKeyProvider: apiKeyProvider,
            localWhisperServiceFactory: localWhisperServiceFactory,
            localFluidAudioServiceFactory: localFluidAudioServiceFactory,
            nativeAppleServiceFactory: nativeAppleServiceFactory,
            customCloudServiceFactory: customCloudServiceFactory,
            remoteServiceFactory: remoteServiceFactory
        ).retranscribe(
            record,
            relativeTo: recordingsDirectory,
            fileManager: fileManager
        )
    }

    @discardableResult
    static func retranscribeWithOutcome<Record: RomaMutableTranscriptionRecord & RomaStoredAudioRecord>(
        _ record: Record,
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default,
        processor: RomaTranscriptionRunProcessor = RomaTranscriptionRunProcessor(),
        defaults: UserDefaults = .standard,
        iOSAppSettingsRunSnapshotProvider: @escaping IOSAppSettingsRunSnapshotProvider,
        apiKeyProvider: @escaping RomaTranscriptionRunProcessor.APIKeyProvider,
        localWhisperServiceFactory: @escaping LocalWhisperServiceFactory,
        localFluidAudioServiceFactory: @escaping LocalFluidAudioServiceFactory = {
            RomaUnsupportedAudioTranscriptionService()
        },
        nativeAppleServiceFactory: @escaping NativeAppleServiceFactory = {
            RomaUnsupportedAudioTranscriptionService()
        },
        customCloudServiceFactory: @escaping CustomCloudServiceFactory = {
            RomaUnsupportedAudioTranscriptionService()
        },
        remoteServiceFactory: @escaping RemoteServiceFactory = { RomaRemoteTranscriptionService(provider: $0) }
    ) async -> RomaStoredAudioRetranscriptionOutcome {
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
            localFluidAudioServiceFactory: localFluidAudioServiceFactory,
            nativeAppleServiceFactory: nativeAppleServiceFactory,
            customCloudServiceFactory: customCloudServiceFactory,
            remoteServiceFactory: remoteServiceFactory
        )
    }

    @discardableResult
    static func retranscribeWithOutcome<Record: RomaMutableTranscriptionRecord & RomaStoredAudioRecord>(
        _ record: Record,
        relativeTo recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default,
        processor: RomaTranscriptionRunProcessor = RomaTranscriptionRunProcessor(),
        runSettingsProvider: @escaping RunSettingsProvider,
        apiKeyProvider: @escaping RomaTranscriptionRunProcessor.APIKeyProvider,
        localWhisperServiceFactory: @escaping LocalWhisperServiceFactory,
        localFluidAudioServiceFactory: @escaping LocalFluidAudioServiceFactory = {
            RomaUnsupportedAudioTranscriptionService()
        },
        nativeAppleServiceFactory: @escaping NativeAppleServiceFactory = {
            RomaUnsupportedAudioTranscriptionService()
        },
        customCloudServiceFactory: @escaping CustomCloudServiceFactory = {
            RomaUnsupportedAudioTranscriptionService()
        },
        remoteServiceFactory: @escaping RemoteServiceFactory = { RomaRemoteTranscriptionService(provider: $0) }
    ) async -> RomaStoredAudioRetranscriptionOutcome {
        await runner(
            processor: processor,
            runSettingsProvider: runSettingsProvider,
            apiKeyProvider: apiKeyProvider,
            localWhisperServiceFactory: localWhisperServiceFactory,
            localFluidAudioServiceFactory: localFluidAudioServiceFactory,
            nativeAppleServiceFactory: nativeAppleServiceFactory,
            customCloudServiceFactory: customCloudServiceFactory,
            remoteServiceFactory: remoteServiceFactory
        ).retranscribeWithOutcome(
            record,
            relativeTo: recordingsDirectory,
            fileManager: fileManager
        )
    }

    private static func runner(
        processor: RomaTranscriptionRunProcessor = RomaTranscriptionRunProcessor(),
        runSettingsProvider: @escaping RunSettingsProvider,
        apiKeyProvider: @escaping RomaTranscriptionRunProcessor.APIKeyProvider,
        localWhisperServiceFactory: @escaping LocalWhisperServiceFactory,
        localFluidAudioServiceFactory: @escaping LocalFluidAudioServiceFactory = {
            RomaUnsupportedAudioTranscriptionService()
        },
        nativeAppleServiceFactory: @escaping NativeAppleServiceFactory = {
            RomaUnsupportedAudioTranscriptionService()
        },
        customCloudServiceFactory: @escaping CustomCloudServiceFactory = {
            RomaUnsupportedAudioTranscriptionService()
        },
        remoteServiceFactory: @escaping RemoteServiceFactory = { RomaRemoteTranscriptionService(provider: $0) }
    ) -> RomaStoredAudioRetranscriptionRunner {
        let serviceFactory = RomaAudioTranscriptionServiceFactory(
            localWhisperServiceFactory: localWhisperServiceFactory,
            localFluidAudioServiceFactory: localFluidAudioServiceFactory,
            nativeAppleServiceFactory: nativeAppleServiceFactory,
            customCloudServiceFactory: customCloudServiceFactory,
            remoteServiceFactory: remoteServiceFactory
        )

        return RomaStoredAudioRetranscriptionRunner(
            processor: processor,
            runSettingsProvider: runSettingsProvider,
            apiKeyProvider: apiKeyProvider,
            transcriptionServiceProvider: { provider in
                serviceFactory.service(for: provider)
            }
        )
    }
}
