import Foundation

public enum VoiceInkProviderModelUse: Sendable {
    case transcription
    case postProcessing
}

public enum VoiceInkProviderModelSelectionPresentation: Equatable, Sendable {
    case fixedModel(String)
    case selectableModels([String])
}

public enum VoiceInkTranscriptionTransport: Sendable {
    case openAICompatible
    case deepgram
    case geminiGenerateContent
    case mistral
    case elevenLabs
    case soniox
    case speechmatics
    case assemblyAI
    case xai
    case localWhisper
}

public enum VoiceInkTranscriptionServiceKind: Sendable {
    case remote
    case localWhisper
}

public enum VoiceInkTranscriptionEmptyTextPolicy: Sendable, Equatable {
    case allow
    case rejectEmpty
    case rejectWhitespace

    public func accepts(_ text: String) -> Bool {
        switch self {
        case .allow:
            return true
        case .rejectEmpty:
            return !text.isEmpty
        case .rejectWhitespace:
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

public enum VoiceInkAPIKeyVerificationTransport: Sendable, Equatable {
    case openAICompatibleModels
    case deepgramProjects
    case geminiModels
    case mistralModels
    case elevenLabsUser
    case sonioxFiles
    case speechmaticsJobs
    case assemblyAITranscripts
    case xaiAPIKey
}

public enum VoiceInkProviderAccessRequirement: Sendable {
    case userAPIKey(account: String, verificationStateKey: String, verificationTransport: VoiceInkAPIKeyVerificationTransport)
    case localWhisperModel
    case bundledService
}

public enum VoiceInkProviderCredential {
    public static func nonBlank(_ key: String?) -> String? {
        guard let key,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return key
    }
}

public struct VoiceInkProviderAPIKeyDraft: Equatable, Sendable {
    private let enteredKey: String?
    private let storedRuntimeKey: String?

    public init(enteredKey: String?, storedRuntimeKey: String?) {
        self.enteredKey = enteredKey
        self.storedRuntimeKey = storedRuntimeKey
    }

    public var hasEnteredKey: Bool {
        enteredKeyForVerification != nil
    }

    public var canVerify: Bool {
        verificationCandidate != nil
    }

    public var verificationCandidate: String? {
        enteredKeyForVerification ?? VoiceInkProviderCredential.nonBlank(storedRuntimeKey)
    }

    public var keyToSaveAfterSuccessfulVerification: String? {
        enteredKeyForVerification
    }

    private var enteredKeyForVerification: String? {
        let trimmed = enteredKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct VoiceInkProviderAPIKeyVerificationApplicationPlan: Equatable, Sendable {
    public let progress: VoiceInkProviderAPIKeyVerificationProgress
    public let keyToSave: String?
    public let shouldMarkKeyVerified: Bool

    public init(
        progress: VoiceInkProviderAPIKeyVerificationProgress,
        keyToSave: String?,
        shouldMarkKeyVerified: Bool
    ) {
        self.progress = progress
        self.keyToSave = keyToSave
        self.shouldMarkKeyVerified = shouldMarkKeyVerified
    }
}

public enum VoiceInkProviderAPIKeyVerificationControl: Equatable, Sendable {
    case progress
    case verifyButton(isDisabled: Bool)
}

public struct VoiceInkProviderAPIKeyFormControlPresentation: Equatable, Sendable {
    public let isSaveButtonDisabled: Bool
    public let verificationControl: VoiceInkProviderAPIKeyVerificationControl

    public init(
        isSaveButtonDisabled: Bool,
        verificationControl: VoiceInkProviderAPIKeyVerificationControl
    ) {
        self.isSaveButtonDisabled = isSaveButtonDisabled
        self.verificationControl = verificationControl
    }
}

public extension VoiceInkProviderAPIKeyDraft {
    func verificationApplicationPlan(
        for result: VoiceInkAPIKeyVerificationResult
    ) -> VoiceInkProviderAPIKeyVerificationApplicationPlan {
        guard result.isValid else {
            return VoiceInkProviderAPIKeyVerificationApplicationPlan(
                progress: .failure(message: result.errorMessage),
                keyToSave: nil,
                shouldMarkKeyVerified: false
            )
        }

        return VoiceInkProviderAPIKeyVerificationApplicationPlan(
            progress: .success,
            keyToSave: keyToSaveAfterSuccessfulVerification,
            shouldMarkKeyVerified: true
        )
    }

    static func missingVerificationCandidatePlan(
        message: String? = nil
    ) -> VoiceInkProviderAPIKeyVerificationApplicationPlan {
        VoiceInkProviderAPIKeyVerificationApplicationPlan(
            progress: .failure(message: message),
            keyToSave: nil,
            shouldMarkKeyVerified: false
        )
    }
}

public struct VoiceInkProviderAPIKeyFormState: Equatable, Sendable {
    public var enteredKey: String
    public var verificationProgress: VoiceInkProviderAPIKeyVerificationProgress
    public var isEditing: Bool

    public init(
        enteredKey: String = "",
        verificationProgress: VoiceInkProviderAPIKeyVerificationProgress = .idle,
        isEditing: Bool = true
    ) {
        self.enteredKey = enteredKey
        self.verificationProgress = verificationProgress
        self.isEditing = isEditing
    }

    public static func loaded(storedKey: String, isVerified: Bool) -> Self {
        Self(
            enteredKey: storedKey,
            verificationProgress: .idle,
            isEditing: !isVerified
        )
    }

    public func draft(storedRuntimeKey: String?) -> VoiceInkProviderAPIKeyDraft {
        VoiceInkProviderAPIKeyDraft(
            enteredKey: enteredKey,
            storedRuntimeKey: storedRuntimeKey
        )
    }

    public func editingStoredKey(_ storedKey: String) -> Self {
        Self(
            enteredKey: storedKey,
            verificationProgress: .idle,
            isEditing: true
        )
    }

    public func keyEdited() -> Self {
        Self(
            enteredKey: enteredKey,
            verificationProgress: .idle,
            isEditing: isEditing
        )
    }

    public func verifying() -> Self {
        Self(
            enteredKey: enteredKey,
            verificationProgress: .verifying,
            isEditing: isEditing
        )
    }

    public func applyingVerificationPlan(_ plan: VoiceInkProviderAPIKeyVerificationApplicationPlan) -> Self {
        Self(
            enteredKey: enteredKey,
            verificationProgress: plan.progress,
            isEditing: plan.shouldMarkKeyVerified ? false : isEditing
        )
    }

    public func verificationStartPlan(
        storedRuntimeKey: String?,
        missingCandidatePolicy: VoiceInkProviderAPIKeyMissingVerificationCandidatePolicy
    ) -> VoiceInkProviderAPIKeyVerificationStartPlan {
        let draft = self.draft(storedRuntimeKey: storedRuntimeKey)
        guard let candidate = draft.verificationCandidate else {
            switch missingCandidatePolicy {
            case .keepCurrentState:
                return VoiceInkProviderAPIKeyVerificationStartPlan(
                    formState: self,
                    draft: draft,
                    candidate: nil
                )
            case .applyFailurePlan:
                return VoiceInkProviderAPIKeyVerificationStartPlan(
                    formState: verifying().applyingVerificationPlan(
                        VoiceInkProviderAPIKeyDraft.missingVerificationCandidatePlan()
                    ),
                    draft: draft,
                    candidate: nil
                )
            }
        }

        return VoiceInkProviderAPIKeyVerificationStartPlan(
            formState: verifying(),
            draft: draft,
            candidate: candidate
        )
    }

    public func iOSVisibleResultFeedback(isKeyVerified: Bool) -> VoiceInkProviderAPIKeyVerificationFeedback? {
        guard !isKeyVerified else {
            return nil
        }

        return verificationProgress.iOSResultFeedback
    }

    public func iOSControlPresentation(storedRuntimeKey: String?) -> VoiceInkProviderAPIKeyFormControlPresentation {
        let draft = draft(storedRuntimeKey: storedRuntimeKey)
        return VoiceInkProviderAPIKeyFormControlPresentation(
            isSaveButtonDisabled: !draft.hasEnteredKey,
            verificationControl: verificationProgress.isVerifying
                ? .progress
                : .verifyButton(isDisabled: !draft.canVerify)
        )
    }
}

public enum VoiceInkProviderAPIKeyMissingVerificationCandidatePolicy: Equatable, Sendable {
    case keepCurrentState
    case applyFailurePlan
}

public struct VoiceInkProviderAPIKeyVerificationStartPlan: Equatable, Sendable {
    public let formState: VoiceInkProviderAPIKeyFormState
    public let draft: VoiceInkProviderAPIKeyDraft
    public let candidate: String?

    public init(
        formState: VoiceInkProviderAPIKeyFormState,
        draft: VoiceInkProviderAPIKeyDraft,
        candidate: String?
    ) {
        self.formState = formState
        self.draft = draft
        self.candidate = candidate
    }
}

public struct VoiceInkProviderAPIKeyFormPresentation: Equatable, Sendable {
    public let navigationTitle: String
    public let apiKeySectionTitle: String
    public let apiKeyPlaceholder: String
    public let saveButtonTitle: String
    public let saveButtonSystemImageName: String
    public let verifyButtonTitle: String
    public let verifyButtonSystemImageName: String
    public let changeButtonTitle: String
    public let consoleSectionTitle: String
    public let consoleLinkTitle: String
    public let consoleLeadingSystemImageName: String
    public let consoleTrailingSystemImageName: String

    public static func make(for provider: VoiceInkProviderKind) -> Self {
        let displayName = provider.displayName
        return VoiceInkProviderAPIKeyFormPresentation(
            navigationTitle: displayName,
            apiKeySectionTitle: "\(displayName) API Key",
            apiKeyPlaceholder: "\(displayName) API Key",
            saveButtonTitle: "Save",
            saveButtonSystemImageName: "checkmark.circle.fill",
            verifyButtonTitle: "Verify",
            verifyButtonSystemImageName: "checkmark.seal",
            changeButtonTitle: "Change",
            consoleSectionTitle: "Get API Key",
            consoleLinkTitle: "\(displayName) API Console",
            consoleLeadingSystemImageName: "link",
            consoleTrailingSystemImageName: "arrow.up.right.square"
        )
    }
}

public struct VoiceInkProviderAPIKeyCardPresentation: Equatable, Sendable {
    public let configureButtonTitle: String
    public let configureButtonSystemImageName: String
    public let removeAPIKeyButtonTitle: String
    public let removeAPIKeyButtonSystemImageName: String
    public let configurationSectionTitle: String
    public let apiKeyFieldPlaceholder: String

    public init(providerDisplayName: String) {
        self.configureButtonTitle = "Configure"
        self.configureButtonSystemImageName = "gear"
        self.removeAPIKeyButtonTitle = "Remove API Key"
        self.removeAPIKeyButtonSystemImageName = "trash"
        self.configurationSectionTitle = "API Key Configuration"
        self.apiKeyFieldPlaceholder = "Enter your \(providerDisplayName) API key"
    }
}

public enum VoiceInkProviderAPIKeyVerificationTone: Equatable, Sendable {
    case success
    case failure
}

public struct VoiceInkProviderAPIKeyVerificationFeedback: Equatable, Sendable {
    public let text: String
    public let systemImageName: String?
    public let tone: VoiceInkProviderAPIKeyVerificationTone

    public init(
        text: String,
        systemImageName: String? = nil,
        tone: VoiceInkProviderAPIKeyVerificationTone
    ) {
        self.text = text
        self.systemImageName = systemImageName
        self.tone = tone
    }

    public var effectiveSystemImageName: String {
        systemImageName ?? "info.circle"
    }
}

public enum VoiceInkProviderAPIKeyVerificationProgress: Equatable, Sendable {
    case idle
    case verifying
    case success
    case failure(message: String?)

    public static let unsupportedProviderFailure: VoiceInkProviderAPIKeyVerificationProgress = .failure(
        message: "Unsupported provider"
    )

    public var isVerifying: Bool {
        self == .verifying
    }

    public var isSuccess: Bool {
        self == .success
    }

    public var macOSVerifyButtonTitle: String {
        isVerifying ? "Verifying..." : "Verify"
    }

    public var macOSVerifyButtonSystemImageName: String {
        isSuccess ? "checkmark" : "checkmark.shield"
    }

    public var macOSInlineFeedback: VoiceInkProviderAPIKeyVerificationFeedback? {
        switch self {
        case .idle, .verifying:
            return nil
        case .success:
            return VoiceInkProviderAPIKeyVerificationFeedback(
                text: "API key verified successfully!",
                tone: .success
            )
        case .failure(let message):
            return VoiceInkProviderAPIKeyVerificationFeedback(
                text: message ?? "Verification failed",
                tone: .failure
            )
        }
    }

    public var iOSResultFeedback: VoiceInkProviderAPIKeyVerificationFeedback? {
        switch self {
        case .idle, .verifying:
            return nil
        case .success:
            return Self.iOSVerifiedKeyFeedback
        case .failure:
            return VoiceInkProviderAPIKeyVerificationFeedback(
                text: "Verification failed",
                systemImageName: "xmark.seal",
                tone: .failure
            )
        }
    }

    public static let iOSVerifiedKeyFeedback = VoiceInkProviderAPIKeyVerificationFeedback(
        text: "Key verified",
        systemImageName: "checkmark.seal.fill",
        tone: .success
    )
}

public enum VoiceInkProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case groq
    case openAI
    case deepgram
    case cerebras
    case gemini
    case mistral
    case elevenLabs
    case soniox
    case speechmatics
    case assemblyAI
    case xai
    case localWhisper
    case voiceInk

    public var id: String { rawValue }

    public var apiKeyFormPresentation: VoiceInkProviderAPIKeyFormPresentation {
        VoiceInkProviderAPIKeyFormPresentation.make(for: self)
    }

    public var displayName: String {
        persistedValue
    }

    private var persistedValue: String {
        switch self {
        case .groq:
            return "Groq"
        case .openAI:
            return "OpenAI"
        case .deepgram:
            return "Deepgram"
        case .cerebras:
            return "Cerebras"
        case .gemini:
            return "Gemini"
        case .mistral:
            return "Mistral"
        case .elevenLabs:
            return "ElevenLabs"
        case .soniox:
            return "Soniox"
        case .speechmatics:
            return "Speechmatics"
        case .assemblyAI:
            return "AssemblyAI"
        case .xai:
            return "xAI"
        case .localWhisper:
            return "Local (Whisper)"
        case .voiceInk:
            return "VoiceInk"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let provider = Self.provider(forPersistedValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid provider: \(value)"
            )
        }
        self = provider
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(persistedValue)
    }

    private static func provider(forPersistedValue value: String) -> VoiceInkProviderKind? {
        allCases.first { provider in
            provider.persistedValue == value || provider.rawValue == value
        }
    }

    public var apiBaseURL: URL {
        switch self {
        case .groq:
            return VoiceInkProviderEndpoint.groq.apiBaseURL
        case .openAI:
            return VoiceInkProviderEndpoint.openAI.apiBaseURL
        case .deepgram:
            return VoiceInkProviderEndpoint.deepgram.apiBaseURL
        case .cerebras:
            return VoiceInkProviderEndpoint.cerebras.apiBaseURL
        case .gemini:
            return VoiceInkProviderEndpoint.gemini.apiBaseURL
        case .mistral:
            return VoiceInkProviderEndpoint.mistralAPIBaseURL
        case .elevenLabs:
            return VoiceInkProviderEndpoint.elevenLabsAPIBaseURL
        case .soniox:
            return VoiceInkProviderEndpoint.sonioxAPIBaseURL
        case .speechmatics:
            return VoiceInkProviderEndpoint.speechmaticsAPIBaseURL
        case .assemblyAI:
            return VoiceInkProviderEndpoint.assemblyAIAPIBaseURL
        case .xai:
            return VoiceInkProviderEndpoint.xaiAPIBaseURL
        case .localWhisper:
            return URL(string: "http://localhost")!
        case .voiceInk:
            return VoiceInkProviderEndpoint.groq.apiBaseURL
        }
    }

    public var transcriptionAPIBaseURL: URL {
        switch self {
        case .gemini:
            return VoiceInkProviderEndpoint.geminiNativeAPIBaseURL
        case .groq, .openAI, .deepgram, .cerebras, .mistral, .elevenLabs, .soniox, .speechmatics, .assemblyAI, .xai, .localWhisper, .voiceInk:
            return apiBaseURL
        }
    }

    public var consoleURL: URL {
        switch self {
        case .groq:
            return VoiceInkProviderEndpoint.groq.consoleURL
        case .openAI:
            return VoiceInkProviderEndpoint.openAI.consoleURL
        case .deepgram:
            return VoiceInkProviderEndpoint.deepgram.consoleURL
        case .cerebras:
            return VoiceInkProviderEndpoint.cerebras.consoleURL
        case .gemini:
            return VoiceInkProviderEndpoint.gemini.consoleURL
        case .mistral:
            return URL(string: "https://console.mistral.ai/api-keys")!
        case .elevenLabs:
            return URL(string: "https://elevenlabs.io/speech-synthesis")!
        case .soniox:
            return URL(string: "https://console.soniox.com/")!
        case .speechmatics:
            return URL(string: "https://portal.speechmatics.com/manage-access/")!
        case .assemblyAI:
            return URL(string: "https://www.assemblyai.com/dashboard/api-keys")!
        case .xai:
            return URL(string: "https://console.x.ai/")!
        case .localWhisper:
            return URL(string: "https://github.com/ggerganov/whisper.cpp")!
        case .voiceInk:
            return URL(string: "https://voiceink.app")!
        }
    }

    public var transcriptionTransport: VoiceInkTranscriptionTransport {
        switch self {
        case .deepgram:
            return .deepgram
        case .gemini:
            return .geminiGenerateContent
        case .mistral:
            return .mistral
        case .elevenLabs:
            return .elevenLabs
        case .soniox:
            return .soniox
        case .speechmatics:
            return .speechmatics
        case .assemblyAI:
            return .assemblyAI
        case .xai:
            return .xai
        case .localWhisper:
            return .localWhisper
        case .groq, .openAI, .cerebras, .voiceInk:
            return .openAICompatible
        }
    }

    public var transcriptionServiceKind: VoiceInkTranscriptionServiceKind {
        switch transcriptionTransport {
        case .openAICompatible, .deepgram, .geminiGenerateContent, .mistral, .elevenLabs, .soniox, .speechmatics, .assemblyAI, .xai:
            return .remote
        case .localWhisper:
            return .localWhisper
        }
    }

    public var transcriptionEmptyTextPolicy: VoiceInkTranscriptionEmptyTextPolicy {
        switch self {
        case .groq, .deepgram, .gemini:
            return .rejectEmpty
        case .soniox, .speechmatics, .assemblyAI:
            return .rejectWhitespace
        case .openAI, .cerebras, .mistral, .elevenLabs, .xai, .localWhisper, .voiceInk:
            return .allow
        }
    }

    public var accessRequirement: VoiceInkProviderAccessRequirement {
        switch self {
        case .groq:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.groq,
                verificationStateKey: "groqKeyVerified",
                verificationTransport: .openAICompatibleModels
            )
        case .openAI:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.openAI,
                verificationStateKey: "openAIKeyVerified",
                verificationTransport: .openAICompatibleModels
            )
        case .deepgram:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.deepgram,
                verificationStateKey: "deepgramKeyVerified",
                verificationTransport: .deepgramProjects
            )
        case .cerebras:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.cerebras,
                verificationStateKey: "cerebrasKeyVerified",
                verificationTransport: .openAICompatibleModels
            )
        case .gemini:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.gemini,
                verificationStateKey: "geminiKeyVerified",
                verificationTransport: .geminiModels
            )
        case .mistral:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.mistral,
                verificationStateKey: "mistralKeyVerified",
                verificationTransport: .mistralModels
            )
        case .elevenLabs:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.elevenLabs,
                verificationStateKey: "elevenLabsKeyVerified",
                verificationTransport: .elevenLabsUser
            )
        case .soniox:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.soniox,
                verificationStateKey: "sonioxKeyVerified",
                verificationTransport: .sonioxFiles
            )
        case .speechmatics:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.speechmatics,
                verificationStateKey: "speechmaticsKeyVerified",
                verificationTransport: .speechmaticsJobs
            )
        case .assemblyAI:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.assemblyAI,
                verificationStateKey: "assemblyAIKeyVerified",
                verificationTransport: .assemblyAITranscripts
            )
        case .xai:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.xAI,
                verificationStateKey: "xaiKeyVerified",
                verificationTransport: .xaiAPIKey
            )
        case .localWhisper:
            return .localWhisperModel
        case .voiceInk:
            return .bundledService
        }
    }

    public var apiKeyAccount: String? {
        guard case let .userAPIKey(account, _, _) = accessRequirement else {
            return nil
        }
        return account
    }

    public var apiKeyVerificationStateKey: String? {
        guard case let .userAPIKey(_, verificationStateKey, _) = accessRequirement else {
            return nil
        }
        return verificationStateKey
    }

    public var requiresUserAPIKey: Bool {
        guard case .userAPIKey = accessRequirement else {
            return false
        }
        return true
    }

    public func runtimeAPIKey(userAPIKey: String) -> String {
        switch accessRequirement {
        case .userAPIKey:
            return userAPIKey
        case .localWhisperModel:
            return "local"
        case .bundledService:
            return ""
        }
    }

    public func runtimeAPIKeyIfAvailable(userAPIKey: String) -> String? {
        VoiceInkProviderCredential.nonBlank(runtimeAPIKey(userAPIKey: userAPIKey))
    }

    public func isReady(
        userAPIKey: String,
        userAPIKeyVerified: Bool,
        localWhisperModelAvailable: Bool
    ) -> Bool {
        switch accessRequirement {
        case .userAPIKey:
            return userAPIKeyVerified && VoiceInkProviderCredential.nonBlank(userAPIKey) != nil
        case .localWhisperModel:
            return localWhisperModelAvailable
        case .bundledService:
            return true
        }
    }

    public static var userAPIKeyProviders: [VoiceInkProviderKind] {
        allCases.filter(\.requiresUserAPIKey)
    }

    public static func availableProviders(
        for use: VoiceInkProviderModelUse,
        isProviderReady: (VoiceInkProviderKind) -> Bool
    ) -> [VoiceInkProviderKind] {
        allCases.filter { provider in
            provider.isSelectable(for: use) && isProviderReady(provider)
        }
    }

    public var apiKeyVerificationTransport: VoiceInkAPIKeyVerificationTransport? {
        guard case let .userAPIKey(_, _, verificationTransport) = accessRequirement else {
            return nil
        }
        return verificationTransport
    }

    public var canVerifyAPIKey: Bool {
        apiKeyVerificationTransport != nil
    }

    public var transcriptionModelProvider: VoiceInkTranscriptionModelProvider? {
        switch self {
        case .groq:
            return .groq
        case .openAI:
            return .openAI
        case .deepgram:
            return .deepgram
        case .gemini:
            return .gemini
        case .mistral:
            return .mistral
        case .elevenLabs:
            return .elevenLabs
        case .soniox:
            return .soniox
        case .speechmatics:
            return .speechmatics
        case .assemblyAI:
            return .assemblyAI
        case .xai:
            return .xai
        case .localWhisper:
            return .local
        case .voiceInk:
            return nil
        case .cerebras:
            return nil
        }
    }

    public var aiModelProvider: VoiceInkAIModelProvider? {
        switch self {
        case .groq:
            return .groq
        case .openAI:
            return .openAI
        case .cerebras:
            return .cerebras
        case .gemini:
            return .gemini
        case .deepgram, .mistral, .elevenLabs, .soniox, .speechmatics, .assemblyAI, .xai, .localWhisper, .voiceInk:
            return nil
        }
    }

    public var postProcessingChatCompletionsURL: URL? {
        guard supportsModelUse(.postProcessing) else {
            return nil
        }
        return VoiceInkProviderEndpoint.openAICompatibleChatCompletionsURL(from: apiBaseURL)
    }

    public var postProcessingDefaultModel: String? {
        if let fixedModel = fixedModel(for: .postProcessing) {
            return fixedModel
        }

        guard let provider = aiModelProvider else {
            return nil
        }
        return VoiceInkAIModelCatalog.defaultModel(for: provider)
    }

    public var postProcessingModels: [String]? {
        if let fixedModel = fixedModel(for: .postProcessing) {
            return [fixedModel]
        }

        guard let provider = aiModelProvider else {
            return nil
        }
        return VoiceInkAIModelCatalog.availableModels(for: provider)
    }

    public func fixedModel(for _: VoiceInkProviderModelUse) -> String? {
        nil
    }

    public func supportsModelUse(_ use: VoiceInkProviderModelUse) -> Bool {
        fixedModel(for: use) != nil || !models(for: use).isEmpty
    }

    public func isSelectable(for use: VoiceInkProviderModelUse) -> Bool {
        switch accessRequirement {
        case .bundledService:
            return false
        case .userAPIKey, .localWhisperModel:
            return supportsModelUse(use)
        }
    }

    public func defaultModel(for use: VoiceInkProviderModelUse) -> String? {
        switch use {
        case .transcription:
            fixedModel(for: use) ?? models(for: use).first
        case .postProcessing:
            postProcessingDefaultModel
        }
    }

    public func selectedModel(_ currentModel: String, for use: VoiceInkProviderModelUse) -> String {
        if let fixedModel = fixedModel(for: use) {
            return fixedModel
        }

        let availableModels = models(for: use)
        if availableModels.contains(currentModel) {
            return currentModel
        }

        return defaultModel(for: use) ?? ""
    }

    public func modelSelectionPresentation(for use: VoiceInkProviderModelUse) -> VoiceInkProviderModelSelectionPresentation {
        if let fixedModel = fixedModel(for: use) {
            return .fixedModel(fixedModel)
        }

        return .selectableModels(models(for: use))
    }

    public func models(for use: VoiceInkProviderModelUse) -> [String] {
        switch use {
        case .transcription:
            guard let provider = transcriptionModelProvider else { return [] }
            return VoiceInkTranscriptionModelCatalog.modelNames(for: provider)
        case .postProcessing:
            return postProcessingModels ?? []
        }
    }
}
