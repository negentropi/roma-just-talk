import Foundation

public enum RomaProviderModelUse: Sendable {
    case transcription
    case postProcessing
}

public struct RomaProviderModelSelectionPresentation: Equatable, Sendable {
    public let fixedModelName: String?
    public let selectableModels: [String]

    init(fixedModelName: String? = nil, selectableModels: [String] = []) {
        self.fixedModelName = fixedModelName
        self.selectableModels = selectableModels
    }

}

public enum RomaTranscriptionTransport: Sendable {
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
    case localFluidAudio
    case nativeApple
    case nvidiaRiva
}

public enum RomaTranscriptionServiceKind: Equatable, Sendable {
    case remote
    case streamingOnly
    case customCloud
    case localWhisper
    case localFluidAudio
    case nativeApple
}

public enum RomaTranscriptionEmptyTextPolicy: Sendable, Equatable {
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

public enum RomaAPIKeyVerificationTransport: Sendable, Equatable {
    case openAICompatibleModels
    case customAIChat
    case anthropicMessages
    case deepgramProjects
    case geminiModels
    case mistralModels
    case elevenLabsUser
    case sonioxFiles
    case speechmaticsJobs
    case assemblyAITranscripts
    case xaiAPIKey
    case cartesiaVoices
    case nvidiaRivaConfig
}

public enum RomaProviderAccessRequirement: Sendable {
    case userAPIKey(account: String, verificationStateKey: String, verificationTransport: RomaAPIKeyVerificationTransport)
    case localWhisperModel
    case localFluidAudioModel
    case nativeAppleSpeech
    case customCloudModel
    case localEnhancementService
}

public enum RomaProviderAPIKeyAccount {
    public static let groq = "groqAPIKey"
    public static let deepgram = "deepgramAPIKey"
    public static let cerebras = "cerebrasAPIKey"
    public static let gemini = "geminiAPIKey"
    public static let mistral = "mistralAPIKey"
    public static let elevenLabs = "elevenLabsAPIKey"
    public static let soniox = "sonioxAPIKey"
    public static let speechmatics = "speechmaticsAPIKey"
    public static let assemblyAI = "assemblyAIAPIKey"
    public static let xAI = "xaiAPIKey"
    public static let cartesia = "cartesiaAPIKey"
    public static let nvidia = "nvidiaAPIKey"
    public static let openAI = "openAIAPIKey"
    public static let anthropic = "anthropicAPIKey"
    public static let openRouter = "openRouterAPIKey"
    public static let customAI = "customAPIKey"

    public static func accountIdentifier(forProviderName provider: String) -> String {
        let normalizedProvider = normalized(provider)
        return knownAccountsByProviderName[normalizedProvider] ?? "\(normalizedProvider)APIKey"
    }

    public static func fallbackEnvironmentKey(forProviderName provider: String) -> String? {
        fallbackEnvironmentKeysByProviderName[normalized(provider)]
    }

    public static func customModelAccountIdentifier(forModelId modelId: UUID) -> String {
        "customModel_\(modelId.uuidString)_APIKey"
    }

    private static let knownAccountsByProviderName: [String: String] = [
        "groq": groq,
        "deepgram": deepgram,
        "cerebras": cerebras,
        "gemini": gemini,
        "mistral": mistral,
        "elevenlabs": elevenLabs,
        "soniox": soniox,
        "speechmatics": speechmatics,
        "assemblyai": assemblyAI,
        "xai": xAI,
        "cartesia": cartesia,
        "nvidia": nvidia,
        "openai": openAI,
        "anthropic": anthropic,
        "openrouter": openRouter,
        "custom": customAI
    ]

    private static let fallbackEnvironmentKeysByProviderName: [String: String] = [
        "elevenlabs": "ELEVENLABS_API_KEY",
        "nvidia": "NVIDIA_API_KEY"
    ]

    private static func normalized(_ provider: String) -> String {
        provider.lowercased()
    }
}

public enum RomaProviderCredential {
    public static func nonBlank(_ key: String?) -> String? {
        guard let key,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return key
    }
}

public enum RomaAPIKeyReference {
    public static func resolvedValue(
        _ value: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let variableName: String
        if trimmed.hasPrefix("${"), trimmed.hasSuffix("}") {
            variableName = String(trimmed.dropFirst(2).dropLast())
        } else if trimmed.hasPrefix("$") {
            variableName = String(trimmed.dropFirst())
        } else {
            return trimmed
        }

        guard !variableName.isEmpty,
              variableName.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil,
              let resolvedValue = environment[variableName],
              RomaProviderCredential.nonBlank(resolvedValue) != nil else {
            return nil
        }

        return resolvedValue
    }
}

public enum RomaProviderAPIKeyLookup {
    public static func usableAPIKey(
        storedKey: String?,
        provider: RomaProviderKind,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        usableAPIKey(
            storedKey: storedKey,
            providerName: provider.displayName,
            environment: environment
        )
    }

    public static func usableAPIKey(
        storedKey: String?,
        providerName: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let storedKey,
           let resolvedKey = RomaAPIKeyReference.resolvedValue(storedKey, environment: environment),
           let apiKey = RomaProviderCredential.nonBlank(resolvedKey) {
            return apiKey
        }

        guard let environmentKey = RomaProviderAPIKeyAccount.fallbackEnvironmentKey(forProviderName: providerName),
              let value = environment[environmentKey],
              let apiKey = RomaProviderCredential.nonBlank(value) else {
            return nil
        }

        return apiKey
    }
}

public enum RomaSecretPresentation {
    public static let obfuscatedAPIKeyPlaceholder = "••••••••"

    public static func obfuscatedAPIKey(_ key: String) -> String? {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return nil
        }

        let count = trimmedKey.count
        if count <= 6 {
            return String(repeating: "•", count: count)
        }

        let prefixCount = min(4, count)
        let suffixCount = min(4, max(0, count - prefixCount))
        let start = trimmedKey.prefix(prefixCount)
        let end = trimmedKey.suffix(suffixCount)
        let middleCount = max(4, count - prefixCount - suffixCount)
        return "\(start)\(String(repeating: "•", count: middleCount))\(end)"
    }

    public static func obfuscatedAPIKeyOrPlaceholder(_ key: String) -> String {
        obfuscatedAPIKey(key) ?? obfuscatedAPIKeyPlaceholder
    }
}

public struct RomaProviderAPIKeyDraft: Equatable, Sendable {
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
        enteredKeyForVerification ?? RomaProviderCredential.nonBlank(storedRuntimeKey)
    }

    public var keyToSaveAfterSuccessfulVerification: String? {
        enteredKeyForVerification
    }

    private var enteredKeyForVerification: String? {
        let trimmed = enteredKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct RomaProviderAPIKeyVerificationApplicationPlan: Equatable, Sendable {
    public let progress: RomaProviderAPIKeyVerificationProgress
    public let keyToSave: String?
    public let shouldMarkKeyVerified: Bool

    public init(
        progress: RomaProviderAPIKeyVerificationProgress,
        keyToSave: String?,
        shouldMarkKeyVerified: Bool
    ) {
        self.progress = progress
        self.keyToSave = keyToSave
        self.shouldMarkKeyVerified = shouldMarkKeyVerified
    }

    public static let unsupportedProvider = RomaProviderAPIKeyVerificationApplicationPlan(
        progress: .unsupportedProviderFailure,
        keyToSave: nil,
        shouldMarkKeyVerified: false
    )
}

public struct RomaProviderAPIKeyVerificationPersistencePlan: Equatable, Sendable {
    public let keyToSave: String?
    public let verificationFlagToPersist: Bool

    public init(
        keyToSave: String?,
        verificationFlagToPersist: Bool
    ) {
        self.keyToSave = keyToSave
        self.verificationFlagToPersist = verificationFlagToPersist
    }
}

fileprivate enum RomaProviderAPIKeyVerificationPersistenceAction: Equatable, Sendable {
    case saveKey(String)
    case persistVerificationFlag(Bool)
}

public struct RomaProviderAPIKeyVerificationPersistenceApplicationPlan: Equatable, Sendable {
    fileprivate let actions: [RomaProviderAPIKeyVerificationPersistenceAction]

    fileprivate init(actions: [RomaProviderAPIKeyVerificationPersistenceAction]) {
        self.actions = actions
    }
}

public extension RomaProviderAPIKeyVerificationPersistencePlan {
    var applicationPlan: RomaProviderAPIKeyVerificationPersistenceApplicationPlan {
        var actions: [RomaProviderAPIKeyVerificationPersistenceAction] = []
        if let keyToSave {
            actions.append(.saveKey(keyToSave))
        }
        actions.append(.persistVerificationFlag(verificationFlagToPersist))
        return RomaProviderAPIKeyVerificationPersistenceApplicationPlan(actions: actions)
    }
}

extension RomaProviderAPIKeyVerificationPersistenceApplicationPlan {
    func applyRuntimeState(
        saveKey: (String) -> Void,
        persistVerificationFlag: (Bool) -> Void
    ) {
        for action in actions {
            switch action {
            case .saveKey(let key):
                saveKey(key)
            case .persistVerificationFlag(let flag):
                persistVerificationFlag(flag)
            }
        }
    }
}

public extension RomaProviderAPIKeyVerificationPersistenceApplicationPlan {
    func applySuccessPersistence(
        saveKey: (String) -> Void
    ) -> Bool {
        var verificationFlagToPersist = false
        applyRuntimeState(
            saveKey: saveKey,
            persistVerificationFlag: { verificationFlagToPersist = $0 }
        )

        return verificationFlagToPersist
    }
}

public extension RomaProviderAPIKeyVerificationApplicationPlan {
    var successPersistencePlan: RomaProviderAPIKeyVerificationPersistencePlan? {
        guard shouldMarkKeyVerified else { return nil }
        return RomaProviderAPIKeyVerificationPersistencePlan(
            keyToSave: keyToSave,
            verificationFlagToPersist: true
        )
    }

    var successPersistenceApplicationPlan: RomaProviderAPIKeyVerificationPersistenceApplicationPlan? {
        successPersistencePlan?.applicationPlan
    }

    func applySuccessPersistence(
        saveKey: (String) -> Void
    ) -> Bool {
        guard let successPersistenceApplicationPlan else { return false }
        return successPersistenceApplicationPlan.applySuccessPersistence(saveKey: saveKey)
    }
}

enum RomaProviderAPIKeyVerificationControl: Equatable, Sendable {
    case progress
    case verifyButton(isDisabled: Bool)

    var isProgressVisible: Bool {
        switch self {
        case .progress:
            return true
        case .verifyButton:
            return false
        }
    }

    var isVerifyButtonDisabled: Bool {
        switch self {
        case .progress:
            return true
        case .verifyButton(let isDisabled):
            return isDisabled
        }
    }

    func runtimeAction(
        verify: @escaping () -> Void
    ) -> (() -> Void)? {
        switch self {
        case .progress:
            return nil
        case .verifyButton(let isDisabled):
            return isDisabled ? nil : verify
        }
    }
}

public struct RomaProviderAPIKeyFormControlPresentation: Equatable, Sendable {
    public let isSaveButtonDisabled: Bool
    let verificationControl: RomaProviderAPIKeyVerificationControl

    init(
        isSaveButtonDisabled: Bool,
        verificationControl: RomaProviderAPIKeyVerificationControl
    ) {
        self.isSaveButtonDisabled = isSaveButtonDisabled
        self.verificationControl = verificationControl
    }

    public var isVerificationProgressVisible: Bool {
        verificationControl.isProgressVisible
    }

    public var isVerifyButtonDisabled: Bool {
        verificationControl.isVerifyButtonDisabled
    }

    public func verifyRuntimeAction(
        verify: @escaping () -> Void
    ) -> (() -> Void)? {
        verificationControl.runtimeAction(verify: verify)
    }

    public func saveRuntimeAction(
        save: @escaping () -> Void
    ) -> (() -> Void)? {
        isSaveButtonDisabled ? nil : save
    }
}

public struct RomaProviderAPIKeyCardControlPresentation: Equatable, Sendable {
    public let isAPIKeyFieldDisabled: Bool
    public let isVerifyProgressVisible: Bool
    public let isVerifyButtonDisabled: Bool
    public let verifyButtonTitle: String
    public let verifyButtonSystemImageName: String
    public let isVerifyButtonSuccess: Bool
    public let inlineFeedback: RomaProviderAPIKeyVerificationFeedback?

    public init(
        isAPIKeyFieldDisabled: Bool,
        isVerifyProgressVisible: Bool,
        isVerifyButtonDisabled: Bool,
        verifyButtonTitle: String,
        verifyButtonSystemImageName: String,
        isVerifyButtonSuccess: Bool,
        inlineFeedback: RomaProviderAPIKeyVerificationFeedback?
    ) {
        self.isAPIKeyFieldDisabled = isAPIKeyFieldDisabled
        self.isVerifyProgressVisible = isVerifyProgressVisible
        self.isVerifyButtonDisabled = isVerifyButtonDisabled
        self.verifyButtonTitle = verifyButtonTitle
        self.verifyButtonSystemImageName = verifyButtonSystemImageName
        self.isVerifyButtonSuccess = isVerifyButtonSuccess
        self.inlineFeedback = inlineFeedback
    }
}

public struct RomaProviderAPIKeyStoredKeyPresentation: Equatable, Sendable {
    public let feedback: RomaProviderAPIKeyVerificationFeedback
    public let obfuscatedKey: String?

    public init(
        feedback: RomaProviderAPIKeyVerificationFeedback,
        obfuscatedKey: String?
    ) {
        self.feedback = feedback
        self.obfuscatedKey = obfuscatedKey
    }
}

public struct RomaProviderAPIKeyEditPlan: Equatable, Sendable {
    public let formState: RomaProviderAPIKeyFormState
    public let verificationFlagToPersist: Bool?

    public init(
        formState: RomaProviderAPIKeyFormState,
        verificationFlagToPersist: Bool?
    ) {
        self.formState = formState
        self.verificationFlagToPersist = verificationFlagToPersist
    }
}

public extension RomaProviderAPIKeyDraft {
    func verificationApplicationPlan(
        for result: RomaAPIKeyVerificationResult
    ) -> RomaProviderAPIKeyVerificationApplicationPlan {
        guard result.isValid else {
            return RomaProviderAPIKeyVerificationApplicationPlan(
                progress: .failure(message: result.errorMessage),
                keyToSave: nil,
                shouldMarkKeyVerified: false
            )
        }

        return RomaProviderAPIKeyVerificationApplicationPlan(
            progress: .success,
            keyToSave: keyToSaveAfterSuccessfulVerification,
            shouldMarkKeyVerified: true
        )
    }

    static func missingVerificationCandidatePlan(
        message: String? = nil
    ) -> RomaProviderAPIKeyVerificationApplicationPlan {
        RomaProviderAPIKeyVerificationApplicationPlan(
            progress: .failure(message: message),
            keyToSave: nil,
            shouldMarkKeyVerified: false
        )
    }
}

public struct RomaProviderAPIKeyFormState: Equatable, Sendable {
    public var enteredKey: String
    public var verificationProgress: RomaProviderAPIKeyVerificationProgress
    public var isEditing: Bool

    public init(
        enteredKey: String = "",
        verificationProgress: RomaProviderAPIKeyVerificationProgress = .idle,
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

    public func draft(storedRuntimeKey: String?) -> RomaProviderAPIKeyDraft {
        RomaProviderAPIKeyDraft(
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

    public func iOSStoredKeyEditPlan(storedKey: String) -> RomaProviderAPIKeyEditPlan {
        RomaProviderAPIKeyEditPlan(
            formState: editingStoredKey(storedKey),
            verificationFlagToPersist: false
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

    public func applyingVerificationPlan(_ plan: RomaProviderAPIKeyVerificationApplicationPlan) -> Self {
        Self(
            enteredKey: enteredKey,
            verificationProgress: plan.progress,
            isEditing: plan.shouldMarkKeyVerified ? false : isEditing
        )
    }

    public func verificationStartPlan(
        storedRuntimeKey: String?,
        missingCandidatePolicy: RomaProviderAPIKeyMissingVerificationCandidatePolicy
    ) -> RomaProviderAPIKeyVerificationStartPlan {
        let draft = self.draft(storedRuntimeKey: storedRuntimeKey)
        guard let candidate = draft.verificationCandidate else {
            switch missingCandidatePolicy {
            case .keepCurrentState:
                return RomaProviderAPIKeyVerificationStartPlan(
                    formState: self,
                    draft: draft,
                    candidate: nil
                )
            case .applyFailurePlan:
                return RomaProviderAPIKeyVerificationStartPlan(
                    formState: verifying().applyingVerificationPlan(
                        RomaProviderAPIKeyDraft.missingVerificationCandidatePlan()
                    ),
                    draft: draft,
                    candidate: nil
                )
            }
        }

        return RomaProviderAPIKeyVerificationStartPlan(
            formState: verifying(),
            draft: draft,
            candidate: candidate
        )
    }

    public func verificationCompletionPlan(
        startPlan: RomaProviderAPIKeyVerificationStartPlan,
        result: RomaAPIKeyVerificationResult
    ) -> RomaProviderAPIKeyVerificationCompletionPlan {
        verificationCompletionPlan(
            applicationPlan: startPlan.draft.verificationApplicationPlan(for: result)
        )
    }

    public func verificationCompletionPlan(
        applicationPlan: RomaProviderAPIKeyVerificationApplicationPlan
    ) -> RomaProviderAPIKeyVerificationCompletionPlan {
        RomaProviderAPIKeyVerificationCompletionPlan(
            formState: applyingVerificationPlan(applicationPlan),
            applicationPlan: applicationPlan
        )
    }

    public func iOSVisibleResultFeedback(isProviderReady: Bool) -> RomaProviderAPIKeyVerificationFeedback? {
        guard !isProviderReady else {
            return nil
        }

        return verificationProgress.iOSResultFeedback
    }

    public func iOSStoredKeyPresentation(storedKey: String) -> RomaProviderAPIKeyStoredKeyPresentation? {
        guard !isEditing else {
            return nil
        }

        return RomaProviderAPIKeyStoredKeyPresentation(
            feedback: RomaProviderAPIKeyVerificationProgress.iOSVerifiedKeyFeedback,
            obfuscatedKey: RomaSecretPresentation.obfuscatedAPIKey(storedKey)
        )
    }

    public func iOSControlPresentation(storedRuntimeKey: String?) -> RomaProviderAPIKeyFormControlPresentation {
        let draft = draft(storedRuntimeKey: storedRuntimeKey)
        return RomaProviderAPIKeyFormControlPresentation(
            isSaveButtonDisabled: !draft.hasEnteredKey,
            verificationControl: verificationProgress.isVerifying
                ? .progress
                : .verifyButton(isDisabled: !draft.canVerify)
        )
    }

    public func macOSCardControlPresentation(storedRuntimeKey: String?) -> RomaProviderAPIKeyCardControlPresentation {
        let draft = draft(storedRuntimeKey: storedRuntimeKey)
        return RomaProviderAPIKeyCardControlPresentation(
            isAPIKeyFieldDisabled: verificationProgress.isVerifying,
            isVerifyProgressVisible: verificationProgress.isVerifying,
            isVerifyButtonDisabled: !draft.canVerify || verificationProgress.isVerifying,
            verifyButtonTitle: verificationProgress.macOSVerifyButtonTitle,
            verifyButtonSystemImageName: verificationProgress.macOSVerifyButtonSystemImageName,
            isVerifyButtonSuccess: verificationProgress.isSuccess,
            inlineFeedback: verificationProgress.macOSInlineFeedback
        )
    }
}

public enum RomaProviderAPIKeyMissingVerificationCandidatePolicy: Equatable, Sendable {
    case keepCurrentState
    case applyFailurePlan
}

public struct RomaProviderAPIKeyVerificationStartPlan: Equatable, Sendable {
    private let formState: RomaProviderAPIKeyFormState
    fileprivate let draft: RomaProviderAPIKeyDraft
    private let candidate: String?

    init(
        formState: RomaProviderAPIKeyFormState,
        draft: RomaProviderAPIKeyDraft,
        candidate: String?
    ) {
        self.formState = formState
        self.draft = draft
        self.candidate = candidate
    }

    @discardableResult
    public func applyRuntimeState<Result>(
        setFormState: (RomaProviderAPIKeyFormState) -> Void,
        verifyCandidate: (String) -> Result
    ) -> Result? {
        setFormState(formState)
        guard let candidate else {
            return nil
        }

        return verifyCandidate(candidate)
    }

    @discardableResult
    public func applyRuntimeState<Result>(
        setFormState: (RomaProviderAPIKeyFormState) -> Void,
        verifyCandidate: (String) async -> Result
    ) async -> Result? {
        setFormState(formState)
        guard let candidate else {
            return nil
        }

        return await verifyCandidate(candidate)
    }
}

public struct RomaProviderAPIKeyVerificationCompletionPlan: Equatable, Sendable {
    public let formState: RomaProviderAPIKeyFormState
    public let applicationPlan: RomaProviderAPIKeyVerificationApplicationPlan

    public init(
        formState: RomaProviderAPIKeyFormState,
        applicationPlan: RomaProviderAPIKeyVerificationApplicationPlan
    ) {
        self.formState = formState
        self.applicationPlan = applicationPlan
    }

    @discardableResult
    public func applyRuntimeState<Result>(
        setFormState: (RomaProviderAPIKeyFormState) -> Void,
        applyVerificationPlan: (RomaProviderAPIKeyVerificationApplicationPlan) -> Result
    ) -> Result {
        setFormState(formState)
        return applyVerificationPlan(applicationPlan)
    }
}

public struct RomaProviderAPIKeyFormPresentation: Equatable, Sendable {
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

    public static func make(for provider: RomaProviderKind) -> Self {
        let displayName = provider.displayName
        return RomaProviderAPIKeyFormPresentation(
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

public struct RomaProviderAPIKeyCardPresentation: Equatable, Sendable {
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

public enum RomaProviderAPIKeyVerificationTone: Equatable, Sendable {
    case success
    case failure
}

public struct RomaProviderAPIKeyVerificationFeedback: Equatable, Sendable {
    public let text: String
    public let systemImageName: String?
    public let tone: RomaProviderAPIKeyVerificationTone

    public init(
        text: String,
        systemImageName: String? = nil,
        tone: RomaProviderAPIKeyVerificationTone
    ) {
        self.text = text
        self.systemImageName = systemImageName
        self.tone = tone
    }

    public var effectiveSystemImageName: String {
        systemImageName ?? "info.circle"
    }
}

public enum RomaProviderAPIKeyVerificationProgress: Equatable, Sendable {
    case idle
    case verifying
    case success
    case failure(message: String?)

    public static let unsupportedProviderFailureMessage = "Unsupported provider"
    public static let unsupportedProviderFailure: RomaProviderAPIKeyVerificationProgress = .failure(
        message: unsupportedProviderFailureMessage
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

    public var macOSInlineFeedback: RomaProviderAPIKeyVerificationFeedback? {
        switch self {
        case .idle, .verifying:
            return nil
        case .success:
            return RomaProviderAPIKeyVerificationFeedback(
                text: "API key verified successfully!",
                tone: .success
            )
        case .failure(let message):
            return RomaProviderAPIKeyVerificationFeedback(
                text: message ?? "Verification failed",
                tone: .failure
            )
        }
    }

    public var iOSResultFeedback: RomaProviderAPIKeyVerificationFeedback? {
        switch self {
        case .idle, .verifying:
            return nil
        case .success:
            return Self.iOSVerifiedKeyFeedback
        case .failure:
            return RomaProviderAPIKeyVerificationFeedback(
                text: "Verification failed",
                systemImageName: "xmark.seal",
                tone: .failure
            )
        }
    }

    public static let iOSVerifiedKeyFeedback = RomaProviderAPIKeyVerificationFeedback(
        text: "Key verified",
        systemImageName: "checkmark.seal.fill",
        tone: .success
    )
}

public enum RomaProviderEndpoint: String, CaseIterable, Sendable {
    case groq
    case openAI
    case deepgram
    case cerebras
    case gemini

    public var apiBaseURL: URL {
        switch self {
        case .groq:
            return URL(string: "https://api.groq.com/openai")!
        case .openAI:
            return URL(string: "https://api.openai.com")!
        case .deepgram:
            return URL(string: "https://api.deepgram.com")!
        case .cerebras:
            return URL(string: "https://api.cerebras.ai")!
        case .gemini:
            return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!
        }
    }

    public static var geminiNativeAPIBaseURL: URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta")!
    }

    public static var mistralAPIBaseURL: URL {
        URL(string: "https://api.mistral.ai")!
    }

    public static var elevenLabsAPIBaseURL: URL {
        URL(string: "https://api.elevenlabs.io")!
    }

    public static var xaiAPIBaseURL: URL {
        URL(string: "https://api.x.ai")!
    }

    public static var sonioxAPIBaseURL: URL {
        URL(string: "https://api.soniox.com/v1")!
    }

    public static var speechmaticsAPIBaseURL: URL {
        URL(string: "https://asr.api.speechmatics.com/v2")!
    }

    public static var assemblyAIAPIBaseURL: URL {
        URL(string: "https://api.assemblyai.com")!
    }

    public static var cartesiaAPIBaseURL: URL {
        URL(string: "https://api.cartesia.ai")!
    }

    public static var anthropicAPIBaseURL: URL {
        URL(string: "https://api.anthropic.com")!
    }

    public static var openRouterAPIBaseURL: URL {
        URL(string: "https://openrouter.ai/api")!
    }

    public var chatCompletionsURL: URL? {
        switch self {
        case .groq, .openAI, .cerebras, .gemini:
            return Self.openAICompatibleChatCompletionsURL(from: apiBaseURL)
        case .deepgram:
            return nil
        }
    }

    public var deepgramListenURL: URL? {
        switch self {
        case .deepgram:
            return Self.deepgramListenURL(from: apiBaseURL)
        case .groq, .openAI, .cerebras, .gemini:
            return nil
        }
    }

    public var consoleURL: URL {
        switch self {
        case .groq:
            return URL(string: "https://console.groq.com/keys")!
        case .openAI:
            return URL(string: "https://platform.openai.com/api-keys")!
        case .deepgram:
            return URL(string: "https://console.deepgram.com/api-keys")!
        case .cerebras:
            return URL(string: "https://cloud.cerebras.ai/")!
        case .gemini:
            return URL(string: "https://makersuite.google.com/app/apikey")!
        }
    }

    public static func openAICompatibleModelsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/models")
    }

    public static func openAICompatibleChatCompletionsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/chat/completions")
    }

    public static func openAICompatibleAudioTranscriptionsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/audio/transcriptions")
    }

    public static func deepgramListenURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/listen")
    }

    public static func deepgramProjectsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/projects")
    }

    public static func geminiGenerateContentURL(from baseURL: URL, model: String) -> URL {
        baseURL
            .appendingPathComponent("models")
            .appendingPathComponent("\(model):generateContent")
    }

    public static func geminiModelsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("models")
    }

    public static func mistralAudioTranscriptionsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/audio/transcriptions")
    }

    public static func mistralModelsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/models")
    }

    public static func elevenLabsSpeechToTextURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/speech-to-text")
    }

    public static func elevenLabsUserURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/user")
    }

    public static func xaiSpeechToTextURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/stt")
    }

    public static func xaiAPIKeyURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/api-key")
    }

    public static func sonioxFilesURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("files")
    }

    public static func sonioxTranscriptionsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("transcriptions")
    }

    public static func sonioxTranscriptionURL(from baseURL: URL, id: String) -> URL {
        sonioxTranscriptionsURL(from: baseURL).appendingPathComponent(id)
    }

    public static func sonioxTranscriptURL(from baseURL: URL, id: String) -> URL {
        sonioxTranscriptionURL(from: baseURL, id: id).appendingPathComponent("transcript")
    }

    public static func speechmaticsJobsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("jobs")
    }

    public static func speechmaticsJobURL(from baseURL: URL, id: String) -> URL {
        speechmaticsJobsURL(from: baseURL).appendingPathComponent(id)
    }

    public static func speechmaticsTranscriptURL(from baseURL: URL, id: String) -> URL {
        let url = speechmaticsJobURL(from: baseURL, id: id).appendingPathComponent("transcript")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "format", value: "txt")]
        return components.url!
    }

    public static func assemblyAIUploadURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v2/upload")
    }

    public static func assemblyAITranscriptsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v2/transcript")
    }

    public static func assemblyAITranscriptURL(from baseURL: URL, id: String) -> URL {
        assemblyAITranscriptsURL(from: baseURL).appendingPathComponent(id)
    }

    public static func cartesiaVoicesURL(from baseURL: URL) -> URL {
        let url = baseURL.appendingPathComponent("voices")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: "1")]
        return components.url!
    }
}

public enum RomaProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
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
    case cartesia
    case nvidia
    case anthropic
    case openRouter
    case customAI
    case ollama
    case customCloud
    case localWhisper
    case localFluidAudio
    case nativeApple

    public var id: String { rawValue }

    public var apiKeyFormPresentation: RomaProviderAPIKeyFormPresentation {
        RomaProviderAPIKeyFormPresentation.make(for: self)
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
        case .cartesia:
            return "Cartesia"
        case .nvidia:
            return "NVIDIA"
        case .anthropic:
            return "Anthropic"
        case .openRouter:
            return "OpenRouter"
        case .customAI:
            return "Custom"
        case .ollama:
            return "Ollama"
        case .customCloud:
            return "Custom Cloud"
        case .localWhisper:
            return "Local (Whisper)"
        case .localFluidAudio:
            return "Local (Parakeet)"
        case .nativeApple:
            return "Native Apple"
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

    private static func provider(forPersistedValue value: String) -> RomaProviderKind? {
        allCases.first { provider in
            provider.persistedValue == value || provider.rawValue == value
        }
    }

    public var apiBaseURL: URL {
        switch self {
        case .groq:
            return RomaProviderEndpoint.groq.apiBaseURL
        case .openAI:
            return RomaProviderEndpoint.openAI.apiBaseURL
        case .deepgram:
            return RomaProviderEndpoint.deepgram.apiBaseURL
        case .cerebras:
            return RomaProviderEndpoint.cerebras.apiBaseURL
        case .gemini:
            return RomaProviderEndpoint.gemini.apiBaseURL
        case .mistral:
            return RomaProviderEndpoint.mistralAPIBaseURL
        case .elevenLabs:
            return RomaProviderEndpoint.elevenLabsAPIBaseURL
        case .soniox:
            return RomaProviderEndpoint.sonioxAPIBaseURL
        case .speechmatics:
            return RomaProviderEndpoint.speechmaticsAPIBaseURL
        case .assemblyAI:
            return RomaProviderEndpoint.assemblyAIAPIBaseURL
        case .xai:
            return RomaProviderEndpoint.xaiAPIBaseURL
        case .cartesia:
            return RomaProviderEndpoint.cartesiaAPIBaseURL
        case .nvidia:
            return URL(string: "https://grpc.nvcf.nvidia.com")!
        case .anthropic:
            return RomaProviderEndpoint.anthropicAPIBaseURL
        case .openRouter:
            return RomaProviderEndpoint.openRouterAPIBaseURL
        case .customAI:
            return URL(
                string: RomaDynamicAIProviderPreference.customProviderBaseURL()
            ) ?? URL(string: "http://localhost")!
        case .ollama:
            return URL(
                string: RomaDynamicAIProviderPreference.ollamaBaseURL()
            ) ?? URL(string: RomaDynamicAIProviderPreference.defaultOllamaBaseURL)!
        case .customCloud:
            return URL(string: "http://localhost")!
        case .localWhisper:
            return URL(string: "http://localhost")!
        case .localFluidAudio:
            return URL(string: "https://github.com/FluidInference/FluidAudio")!
        case .nativeApple:
            return URL(string: "https://developer.apple.com/documentation/speech")!
        }
    }

    public var transcriptionAPIBaseURL: URL {
        switch self {
        case .gemini:
            return RomaProviderEndpoint.geminiNativeAPIBaseURL
        case .groq, .openAI, .deepgram, .cerebras, .mistral, .elevenLabs, .soniox, .speechmatics, .assemblyAI, .xai, .cartesia, .nvidia, .anthropic, .openRouter, .customAI, .ollama, .customCloud, .localWhisper, .localFluidAudio, .nativeApple:
            return apiBaseURL
        }
    }

    public var consoleURL: URL {
        switch self {
        case .groq:
            return RomaProviderEndpoint.groq.consoleURL
        case .openAI:
            return RomaProviderEndpoint.openAI.consoleURL
        case .deepgram:
            return RomaProviderEndpoint.deepgram.consoleURL
        case .cerebras:
            return RomaProviderEndpoint.cerebras.consoleURL
        case .gemini:
            return RomaProviderEndpoint.gemini.consoleURL
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
        case .cartesia:
            return URL(string: "https://play.cartesia.ai/keys")!
        case .nvidia:
            return URL(string: "https://build.nvidia.com/nvidia/parakeet-ctc-0_6b-zh-tw/api")!
        case .anthropic:
            return URL(string: "https://console.anthropic.com/settings/keys")!
        case .openRouter:
            return URL(string: "https://openrouter.ai/settings/keys")!
        case .customAI:
            return URL(string: "https://roma-just-talk.com/readme")!
        case .ollama:
            return URL(string: "https://ollama.com")!
        case .customCloud:
            return URL(string: "https://roma-just-talk.com/readme")!
        case .localWhisper:
            return URL(string: "https://github.com/ggerganov/whisper.cpp")!
        case .localFluidAudio:
            return URL(string: "https://github.com/FluidInference/FluidAudio")!
        case .nativeApple:
            return URL(string: "https://developer.apple.com/documentation/speech")!
        }
    }

    public var transcriptionTransport: RomaTranscriptionTransport {
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
        case .nvidia:
            return .nvidiaRiva
        case .cartesia, .customCloud, .anthropic, .openRouter, .customAI, .ollama:
            return .openAICompatible
        case .localWhisper:
            return .localWhisper
        case .localFluidAudio:
            return .localFluidAudio
        case .nativeApple:
            return .nativeApple
        case .groq, .openAI, .cerebras:
            return .openAICompatible
        }
    }

    public var transcriptionServiceKind: RomaTranscriptionServiceKind {
        if self == .cartesia {
            return .streamingOnly
        }
        if self == .customCloud {
            return .customCloud
        }

        switch transcriptionTransport {
        case .openAICompatible, .deepgram, .geminiGenerateContent, .mistral, .elevenLabs, .soniox, .speechmatics, .assemblyAI, .xai, .nvidiaRiva:
            return .remote
        case .localWhisper:
            return .localWhisper
        case .localFluidAudio:
            return .localFluidAudio
        case .nativeApple:
            return .nativeApple
        }
    }

    public var transcriptionEmptyTextPolicy: RomaTranscriptionEmptyTextPolicy {
        switch self {
        case .groq, .deepgram, .gemini:
            return .rejectEmpty
        case .soniox, .speechmatics, .assemblyAI, .nvidia, .localFluidAudio, .nativeApple:
            return .rejectWhitespace
        case .openAI, .cerebras, .mistral, .elevenLabs, .xai, .cartesia, .anthropic, .openRouter, .customAI, .ollama, .customCloud, .localWhisper:
            return .allow
        }
    }

    public var accessRequirement: RomaProviderAccessRequirement {
        switch self {
        case .groq:
            return .userAPIKey(
                account: RomaProviderAPIKeyAccount.groq,
                verificationStateKey: "groqKeyVerified",
                verificationTransport: .openAICompatibleModels
            )
        case .openAI:
            return .userAPIKey(
                account: RomaProviderAPIKeyAccount.openAI,
                verificationStateKey: "openAIKeyVerified",
                verificationTransport: .openAICompatibleModels
            )
        case .deepgram:
            return .userAPIKey(
                account: RomaProviderAPIKeyAccount.deepgram,
                verificationStateKey: "deepgramKeyVerified",
                verificationTransport: .deepgramProjects
            )
        case .cerebras:
            return .userAPIKey(
                account: RomaProviderAPIKeyAccount.cerebras,
                verificationStateKey: "cerebrasKeyVerified",
                verificationTransport: .openAICompatibleModels
            )
        case .gemini:
            return .userAPIKey(
                account: RomaProviderAPIKeyAccount.gemini,
                verificationStateKey: "geminiKeyVerified",
                verificationTransport: .geminiModels
            )
        case .mistral:
            return .userAPIKey(
                account: RomaProviderAPIKeyAccount.mistral,
                verificationStateKey: "mistralKeyVerified",
                verificationTransport: .mistralModels
            )
        case .elevenLabs:
            return .userAPIKey(
                account: RomaProviderAPIKeyAccount.elevenLabs,
                verificationStateKey: "elevenLabsKeyVerified",
                verificationTransport: .elevenLabsUser
            )
        case .soniox:
            return .userAPIKey(
                account: RomaProviderAPIKeyAccount.soniox,
                verificationStateKey: "sonioxKeyVerified",
                verificationTransport: .sonioxFiles
            )
        case .speechmatics:
            return .userAPIKey(
                account: RomaProviderAPIKeyAccount.speechmatics,
                verificationStateKey: "speechmaticsKeyVerified",
                verificationTransport: .speechmaticsJobs
            )
        case .assemblyAI:
            return .userAPIKey(
                account: RomaProviderAPIKeyAccount.assemblyAI,
                verificationStateKey: "assemblyAIKeyVerified",
                verificationTransport: .assemblyAITranscripts
            )
        case .xai:
            return .userAPIKey(
                account: RomaProviderAPIKeyAccount.xAI,
                verificationStateKey: "xaiKeyVerified",
                verificationTransport: .xaiAPIKey
            )
        case .nvidia:
            return .userAPIKey(
                account: RomaProviderAPIKeyAccount.nvidia,
                verificationStateKey: "nvidiaKeyVerified",
                verificationTransport: .nvidiaRivaConfig
            )
        case .cartesia:
            return .userAPIKey(
                account: RomaProviderAPIKeyAccount.cartesia,
                verificationStateKey: "cartesiaKeyVerified",
                verificationTransport: .cartesiaVoices
            )
        case .anthropic:
            return .userAPIKey(
                account: RomaProviderAPIKeyAccount.anthropic,
                verificationStateKey: "anthropicKeyVerified",
                verificationTransport: .anthropicMessages
            )
        case .openRouter:
            return .userAPIKey(
                account: RomaProviderAPIKeyAccount.openRouter,
                verificationStateKey: "openRouterKeyVerified",
                verificationTransport: .openAICompatibleModels
            )
        case .customAI:
            return .userAPIKey(
                account: RomaProviderAPIKeyAccount.customAI,
                verificationStateKey: "customAIKeyVerified",
                verificationTransport: .customAIChat
            )
        case .ollama:
            return .localEnhancementService
        case .customCloud:
            return .customCloudModel
        case .localWhisper:
            return .localWhisperModel
        case .localFluidAudio:
            return .localFluidAudioModel
        case .nativeApple:
            return .nativeAppleSpeech
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
        case .localFluidAudioModel:
            return "local-fluidaudio"
        case .nativeAppleSpeech:
            return "native-apple"
        case .customCloudModel:
            return "custom-cloud"
        case .localEnhancementService:
            return "local-ollama"
        }
    }

    public func runtimeAPIKeyIfAvailable(userAPIKey: String) -> String? {
        RomaProviderCredential.nonBlank(runtimeAPIKey(userAPIKey: userAPIKey))
    }

    public var isSupportedOnCurrentOS: Bool {
        guard self == .nvidia else { return true }
        if #available(macOS 15, iOS 18, *) { return true }
        return false
    }

    public func isReady(
        userAPIKey: String,
        userAPIKeyVerified: Bool,
        localWhisperModelAvailable: Bool,
        localFluidAudioModelAvailable: Bool = false,
        nativeAppleSpeechAvailable: Bool = false,
        customCloudModelAvailable: Bool = false,
        localEnhancementServiceAvailable: Bool = false
    ) -> Bool {
        guard isSupportedOnCurrentOS else { return false }
        switch accessRequirement {
        case .userAPIKey:
            return userAPIKeyVerified && RomaProviderCredential.nonBlank(userAPIKey) != nil
        case .localWhisperModel:
            return localWhisperModelAvailable
        case .localFluidAudioModel:
            return localFluidAudioModelAvailable
        case .nativeAppleSpeech:
            return nativeAppleSpeechAvailable
        case .customCloudModel:
            return customCloudModelAvailable
        case .localEnhancementService:
            return localEnhancementServiceAvailable
        }
    }

    public static var userAPIKeyProviders: [RomaProviderKind] {
        allCases.filter(\.requiresUserAPIKey)
    }

    public static func availableProviders(
        for use: RomaProviderModelUse,
        isProviderReady: (RomaProviderKind) -> Bool
    ) -> [RomaProviderKind] {
        allCases.filter { provider in
            provider.isSelectable(for: use) && isProviderReady(provider)
        }
    }

    public var apiKeyVerificationTransport: RomaAPIKeyVerificationTransport? {
        guard case let .userAPIKey(_, _, verificationTransport) = accessRequirement else {
            return nil
        }
        return verificationTransport
    }

    public var canVerifyAPIKey: Bool {
        apiKeyVerificationTransport != nil
    }

    public var transcriptionModelProvider: RomaTranscriptionModelProvider? {
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
        case .cartesia:
            return .cartesia
        case .nvidia:
            return .nvidia
        case .anthropic, .openRouter, .customAI, .ollama, .customCloud:
            return nil
        case .localWhisper:
            return .local
        case .localFluidAudio:
            return nil
        case .nativeApple:
            return .nativeApple
        case .cerebras:
            return nil
        }
    }

    public var aiModelProvider: RomaAIModelProvider? {
        switch self {
        case .groq:
            return .groq
        case .openAI:
            return .openAI
        case .cerebras:
            return .cerebras
        case .gemini:
            return .gemini
        case .mistral:
            return .mistral
        case .anthropic:
            return .anthropic
        case .openRouter:
            return .openRouter
        case .customAI:
            return nil
        case .ollama:
            return nil
        case .deepgram, .elevenLabs, .soniox, .speechmatics, .assemblyAI, .xai, .cartesia, .nvidia, .customCloud, .localWhisper, .localFluidAudio, .nativeApple:
            return nil
        }
    }

    public var postProcessingChatCompletionsURL: URL? {
        guard supportsModelUse(.postProcessing) else {
            return nil
        }
        if self == .anthropic {
            return aiModelProvider?.postProcessingRequestURL
        }
        if self == .customAI {
            return URL(string: RomaDynamicAIProviderPreference.customProviderBaseURL())
        }
        return RomaProviderEndpoint.openAICompatibleChatCompletionsURL(from: apiBaseURL)
    }

    public var postProcessingDefaultModel: String? {
        if self == .ollama {
            return RomaProviderCredential.nonBlank(
                RomaDynamicAIProviderPreference.ollamaRuntimeSelectedModel()
            )
        }
        if self == .customAI {
            return RomaProviderCredential.nonBlank(
                RomaDynamicAIProviderPreference.customProviderModel()
            )
        }
        if let fixedModel = fixedModel(for: .postProcessing) {
            return fixedModel
        }

        guard let provider = aiModelProvider else {
            return nil
        }
        return RomaAIModelCatalog.defaultModel(for: provider)
    }

    public var postProcessingModels: [String]? {
        if self == .ollama {
            return postProcessingDefaultModel.map { [$0] } ?? []
        }
        if self == .customAI {
            return postProcessingDefaultModel.map { [$0] } ?? []
        }
        if self == .openRouter {
            let cachedModels = RomaDynamicAIProviderPreference.openRouterModels()
            return cachedModels.isEmpty
                ? [RomaAIModelCatalog.defaultModel(for: .openRouter)]
                : cachedModels
        }
        if let fixedModel = fixedModel(for: .postProcessing) {
            return [fixedModel]
        }

        guard let provider = aiModelProvider else {
            return nil
        }
        return RomaAIModelCatalog.availableModels(for: provider)
    }

    public func fixedModel(for _: RomaProviderModelUse) -> String? {
        nil
    }

    public func supportsModelUse(_ use: RomaProviderModelUse) -> Bool {
        if self == .customCloud {
            return use == .transcription
        }
        return fixedModel(for: use) != nil || !models(for: use).isEmpty
    }

    public func isSelectable(for use: RomaProviderModelUse) -> Bool {
        supportsModelUse(use)
    }

    public func defaultModel(for use: RomaProviderModelUse) -> String? {
        switch use {
        case .transcription:
            fixedModel(for: use) ?? models(for: use).first
        case .postProcessing:
            postProcessingDefaultModel
        }
    }

    public func selectedModel(_ currentModel: String, for use: RomaProviderModelUse) -> String {
        if self == .customCloud, use == .transcription {
            return currentModel
        }
        if let fixedModel = fixedModel(for: use) {
            return fixedModel
        }

        let availableModels = models(for: use)
        if availableModels.contains(currentModel) {
            return currentModel
        }

        return defaultModel(for: use) ?? ""
    }

    public func modelSelectionPresentation(for use: RomaProviderModelUse) -> RomaProviderModelSelectionPresentation {
        if let fixedModel = fixedModel(for: use) {
            return RomaProviderModelSelectionPresentation(fixedModelName: fixedModel)
        }

        return RomaProviderModelSelectionPresentation(selectableModels: models(for: use))
    }

    public func models(for use: RomaProviderModelUse) -> [String] {
        switch use {
        case .transcription:
            if self == .localFluidAudio {
                return RomaTranscriptionModelCatalog.fluidAudioModels.map(\.name)
            }
            guard let provider = transcriptionModelProvider else { return [] }
            return RomaTranscriptionModelCatalog.modelNames(for: provider)
        case .postProcessing:
            return postProcessingModels ?? []
        }
    }
}
