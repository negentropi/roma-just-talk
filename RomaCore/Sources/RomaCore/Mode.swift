import Foundation

public struct RomaModeRuntimeConfiguration: Equatable, Sendable {
    public let transcriptionProvider: RomaProviderKind
    public let transcriptionModel: String
    public let postProcessingProvider: RomaProviderKind
    public let postProcessingModel: String
    public let prompt: String
    public let promptName: String?
    public let isPostProcessingEnabled: Bool

    public init(
        transcriptionProvider: RomaProviderKind,
        transcriptionModel: String,
        postProcessingProvider: RomaProviderKind,
        postProcessingModel: String,
        prompt: String,
        promptName: String? = nil,
        isPostProcessingEnabled: Bool
    ) {
        self.transcriptionProvider = transcriptionProvider
        self.transcriptionModel = transcriptionModel
        self.postProcessingProvider = postProcessingProvider
        self.postProcessingModel = postProcessingModel
        self.prompt = prompt
        self.promptName = promptName
        self.isPostProcessingEnabled = isPostProcessingEnabled
    }

    public func applyingPrompt(_ prompt: RomaCustomPrompt?, forceEnablement: Bool = false) -> Self {
        return RomaModeRuntimeConfiguration(
            transcriptionProvider: transcriptionProvider,
            transcriptionModel: transcriptionModel,
            postProcessingProvider: postProcessingProvider,
            postProcessingModel: postProcessingModel,
            prompt: prompt?.finalPromptText ?? self.prompt,
            promptName: prompt?.title ?? promptName,
            isPostProcessingEnabled: isPostProcessingEnabled || forceEnablement
        )
    }

    public static var fallback: RomaModeRuntimeConfiguration {
        Mode.defaultLocalWhisper().runtimeConfiguration
    }
}

public struct RomaModeSelectionPresentation: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case hidden
        case singleModeName(String)
        case picker
    }

    let kind: Kind
    public static let controlTitle = "Mode"

    init(kind: Kind) {
        self.kind = kind
    }

    public var shouldShowControl: Bool {
        kind != .hidden
    }

    public var shouldShowPicker: Bool {
        kind == .picker
    }

    public var singleModeName: String? {
        guard case .singleModeName(let name) = kind else {
            return nil
        }

        return name
    }
}

public struct RomaModeSummaryPresentation: Equatable, Sendable {
    public let title: String
    public let transcriptionText: String
    public let postProcessingText: String?
}

public struct RomaModeFormPresentation: Equatable, Sendable {
    public let navigationTitle: String
    public let modeDetailsSectionTitle: String
    public let modeNamePlaceholder: String
    public let transcriptionSectionTitle: String
    public let postProcessingSectionTitle: String
    public let postProcessingFooterText: String?
    public let enablePostProcessingTitle: String
    public let providerPickerTitle: String
    public let promptTemplatePickerTitle: String
    public let customPromptPlaceholder: String
    public let modelFieldTitle: String
    public let saveButtonTitle: String

    public static func make(
        isEditing: Bool,
        isPostProcessingEnabled: Bool
    ) -> Self {
        RomaModeFormPresentation(
            navigationTitle: isEditing ? "Edit Mode" : "New Mode",
            modeDetailsSectionTitle: "Mode Details",
            modeNamePlaceholder: "Mode Name",
            transcriptionSectionTitle: "Transcription",
            postProcessingSectionTitle: "Post-processing",
            postProcessingFooterText: isPostProcessingEnabled
                ? "Configure how the raw transcription should be processed and refined."
                : nil,
            enablePostProcessingTitle: "Enable Post-processing",
            providerPickerTitle: "Provider",
            promptTemplatePickerTitle: "Prompt Template",
            customPromptPlaceholder: "Custom Prompt",
            modelFieldTitle: "Model",
            saveButtonTitle: "Save"
        )
    }
}

public struct RomaModeFormStatePresentation: Equatable, Sendable {
    public let shouldShowPostProcessingControls: Bool
    public let shouldShowCustomPromptField: Bool
    public let isSaveButtonDisabled: Bool

    public init(
        shouldShowPostProcessingControls: Bool,
        shouldShowCustomPromptField: Bool,
        isSaveButtonDisabled: Bool
    ) {
        self.shouldShowPostProcessingControls = shouldShowPostProcessingControls
        self.shouldShowCustomPromptField = shouldShowCustomPromptField
        self.isSaveButtonDisabled = isSaveButtonDisabled
    }
}

public enum RomaPostProcessingTemplateType: String, CaseIterable, Codable, Sendable {
    case custom = "Custom"
    case summary = "Summary"
    case keyPoints = "Key Points"
    case rewrite = "Rewrite"
    case transcriptCleanup = "Clean Transcript"

    public var displayName: String {
        rawValue
    }

    public var prompt: String {
        switch self {
        case .custom:
            return ""
        case .summary:
            return "Please provide a concise summary of the following transcription, capturing the main points and key information in a clear and organized manner:"
        case .keyPoints:
            return "Please extract the key points from the following transcription and present them as a bulleted list, highlighting the most important information:"
        case .rewrite:
            return "Please rewrite the following transcription to improve clarity, grammar, and flow while preserving the original meaning and intent:"
        case .transcriptCleanup:
            return "Please clean up the following transcription by correcting any errors, removing filler words, and improving readability while maintaining the speaker's original meaning and tone:"
        }
    }
}

public struct RomaPostProcessingPromptTemplate: Identifiable, Codable, Sendable {
    public let id = UUID()
    public var type: RomaPostProcessingTemplateType
    public var customPrompt: String

    private enum CodingKeys: String, CodingKey {
        case type
        case customPrompt
    }

    public init(type: RomaPostProcessingTemplateType, customPrompt: String = "") {
        self.type = type
        self.customPrompt = customPrompt
    }

    public var effectivePrompt: String {
        switch type {
        case .custom:
            return customPrompt
        default:
            return type.prompt
        }
    }

    public var description: String {
        switch type {
        case .custom:
            return customPrompt.isEmpty ? "Custom prompt (empty)" : "Custom: \(customPrompt.prefix(50))..."
        default:
            return type.displayName
        }
    }
}

public struct RomaModeFormProviderAvailability: Equatable, Sendable {
    public let transcriptionProviders: [RomaProviderKind]
    public let postProcessingProviders: [RomaProviderKind]

    public init(
        transcriptionProviders: [RomaProviderKind],
        postProcessingProviders: [RomaProviderKind]
    ) {
        self.transcriptionProviders = transcriptionProviders
        self.postProcessingProviders = postProcessingProviders
    }

    public func canSave(_ mode: Mode) -> Bool {
        mode.isSaveableDraft(providerAvailability: self)
    }

    public func repairedMode(_ mode: Mode) -> Mode {
        var repairedMode = mode
        repairedMode.repairProviderSelection(providerAvailability: self)
        return repairedMode
    }

    public func formStatePresentation(for mode: Mode) -> RomaModeFormStatePresentation {
        RomaModeFormStatePresentation(
            shouldShowPostProcessingControls: mode.isPostProcessingEnabled,
            shouldShowCustomPromptField: mode.isPostProcessingEnabled && mode.promptTemplate.type == .custom,
            isSaveButtonDisabled: !canSave(mode)
        )
    }
}

public struct RomaModeFormDraftState {
    public var mode: Mode

    public init(
        existingMode: Mode?,
        providerAvailability: RomaModeFormProviderAvailability
    ) {
        self.mode = existingMode ?? providerAvailability.repairedMode(Mode(name: ""))
    }

    public mutating func repairProviderAvailability(_ availability: RomaModeFormProviderAvailability) {
        mode = availability.repairedMode(mode)
    }
}

public struct RomaModeListRepairPlan {
    public let modes: [Mode]
    public let selectedModeId: UUID?
    public let shouldReplaceModes: Bool

    public init(
        modes: [Mode],
        selectedModeId: UUID?,
        shouldReplaceModes: Bool
    ) {
        self.modes = modes
        self.selectedModeId = selectedModeId
        self.shouldReplaceModes = shouldReplaceModes
    }
}

public struct RomaModeSettingsRepairPlan {
    public let modes: [Mode]
    public let selectedModeId: UUID?
    public let selectedTranscriptionLanguage: String
    public let shouldReplaceModes: Bool

    public init(
        modes: [Mode],
        selectedModeId: UUID?,
        selectedTranscriptionLanguage: String,
        shouldReplaceModes: Bool
    ) {
        self.modes = modes
        self.selectedModeId = selectedModeId
        self.selectedTranscriptionLanguage = selectedTranscriptionLanguage
        self.shouldReplaceModes = shouldReplaceModes
    }

    public func shouldApplySelectedModeId(from currentSelectedModeId: UUID?) -> Bool {
        currentSelectedModeId != selectedModeId
    }

    public func shouldApplySelectedTranscriptionLanguage(from currentLanguage: String) -> Bool {
        currentLanguage != selectedTranscriptionLanguage
    }

    func applicationActions(
        currentSelectedModeId: UUID?,
        currentSelectedTranscriptionLanguage: String
    ) -> [RomaModeSettingsRepairAction] {
        var actions: [RomaModeSettingsRepairAction] = []
        if shouldReplaceModes {
            actions.append(.replaceModes(modes))
        }
        if shouldApplySelectedModeId(from: currentSelectedModeId) {
            actions.append(.selectMode(selectedModeId))
        }
        if shouldApplySelectedTranscriptionLanguage(from: currentSelectedTranscriptionLanguage) {
            actions.append(.selectTranscriptionLanguage(selectedTranscriptionLanguage))
        }
        return actions
    }
}

enum RomaModeSettingsRepairAction {
    case replaceModes([Mode])
    case selectMode(UUID?)
    case selectTranscriptionLanguage(String)
}

public extension RomaModeSettingsRepairPlan {
    func applyRuntimeState(
        currentSelectedModeId: UUID?,
        currentSelectedTranscriptionLanguage: String,
        replaceModes: ([Mode]) -> Void,
        selectMode: (UUID?) -> Void,
        selectTranscriptionLanguage: (String) -> Void
    ) {
        for action in applicationActions(
            currentSelectedModeId: currentSelectedModeId,
            currentSelectedTranscriptionLanguage: currentSelectedTranscriptionLanguage
        ) {
            switch action {
            case .replaceModes(let modes):
                replaceModes(modes)
            case .selectMode(let selectedModeId):
                selectMode(selectedModeId)
            case .selectTranscriptionLanguage(let language):
                selectTranscriptionLanguage(language)
            }
        }
    }
}

public enum RomaModeListPolicy {
    public static func appending(_ mode: Mode, to modes: [Mode]) -> [Mode] {
        modes + [mode]
    }

    public static func replacing(
        modeId: UUID,
        with updatedMode: Mode,
        in modes: [Mode]
    ) -> [Mode]? {
        guard let index = modes.firstIndex(where: { $0.id == modeId }) else {
            return nil
        }

        var updatedModes = modes
        updatedModes[index] = updatedMode
        return updatedModes
    }

    public static func removing(at offsets: IndexSet, from modes: [Mode]) -> [Mode] {
        RomaPreferenceList.removing(at: offsets, from: modes)
    }

    public static func defaultModeRepairPlan(
        modes: [Mode],
        selectedModeId: UUID?
    ) -> RomaModeListRepairPlan {
        guard !modes.isEmpty else {
            let defaultSelection = Mode.defaultModesAndSelection()
            return RomaModeListRepairPlan(
                modes: defaultSelection.modes,
                selectedModeId: defaultSelection.selectedModeId,
                shouldReplaceModes: true
            )
        }

        return RomaModeListRepairPlan(
            modes: modes,
            selectedModeId: modes.repairedSelectedModeId(selectedModeId),
            shouldReplaceModes: false
        )
    }
}

public enum RomaModeSettingsPolicy {
    public static func repairPlan(
        modes: [Mode],
        selectedModeId: UUID?,
        selectedTranscriptionLanguage: String
    ) -> RomaModeSettingsRepairPlan {
        makeRepairPlan(
            modes: modes,
            selectedModeId: modes.repairedSelectedModeId(selectedModeId),
            selectedTranscriptionLanguage: selectedTranscriptionLanguage,
            shouldReplaceModes: false
        )
    }

    public static func defaultModeRepairPlan(
        modes: [Mode],
        selectedModeId: UUID?,
        selectedTranscriptionLanguage: String
    ) -> RomaModeSettingsRepairPlan {
        let listPlan = RomaModeListPolicy.defaultModeRepairPlan(
            modes: modes,
            selectedModeId: selectedModeId
        )

        return makeRepairPlan(
            modes: listPlan.modes,
            selectedModeId: listPlan.selectedModeId,
            selectedTranscriptionLanguage: selectedTranscriptionLanguage,
            shouldReplaceModes: listPlan.shouldReplaceModes
        )
    }

    private static func makeRepairPlan(
        modes: [Mode],
        selectedModeId: UUID?,
        selectedTranscriptionLanguage: String,
        shouldReplaceModes: Bool
    ) -> RomaModeSettingsRepairPlan {
        RomaModeSettingsRepairPlan(
            modes: modes,
            selectedModeId: selectedModeId,
            selectedTranscriptionLanguage: modes.repairedSelectedTranscriptionLanguage(
                selectedTranscriptionLanguage,
                selectedModeId: selectedModeId
            ),
            shouldReplaceModes: shouldReplaceModes
        )
    }
}

public struct Mode: Identifiable, Codable {
    public let id: UUID
    public var name: String

    public var transcriptionProvider: RomaProviderKind
    public var transcriptionModel: String

    public var isPostProcessingEnabled: Bool
    public var postProcessingProvider: RomaProviderKind
    public var postProcessingModel: String
    public var promptTemplate: RomaPostProcessingPromptTemplate
    public var selectedPromptId: UUID?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case transcriptionProvider
        case transcriptionModel
        case isPostProcessingEnabled
        case postProcessingProvider
        case postProcessingModel
        case promptTemplate
        case selectedPromptId
    }

    public init(
        name: String,
        transcriptionProvider: RomaProviderKind = .groq,
        transcriptionModel: String? = nil,
        isPostProcessingEnabled: Bool = false,
        postProcessingProvider: RomaProviderKind = .groq,
        postProcessingModel: String? = nil,
        promptTemplate: RomaPostProcessingPromptTemplate? = nil,
        selectedPromptId: UUID? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.transcriptionProvider = transcriptionProvider
        self.transcriptionModel = transcriptionModel
            ?? transcriptionProvider.defaultModel(for: .transcription)
            ?? ""
        self.isPostProcessingEnabled = isPostProcessingEnabled
        self.postProcessingProvider = postProcessingProvider
        self.postProcessingModel = postProcessingModel
            ?? postProcessingProvider.defaultModel(for: .postProcessing)
            ?? RomaAIModelCatalog.defaultModel(for: .groq)
        self.promptTemplate = promptTemplate ?? RomaPostProcessingPromptTemplate(type: .summary)
        self.selectedPromptId = selectedPromptId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isPostProcessingEnabled = try container.decode(Bool.self, forKey: .isPostProcessingEnabled)
        promptTemplate = try container.decode(RomaPostProcessingPromptTemplate.self, forKey: .promptTemplate)
        selectedPromptId = try container.decodeIfPresent(UUID.self, forKey: .selectedPromptId)

        let transcriptionProviderValue = try container.decode(String.self, forKey: .transcriptionProvider)
        if Self.isLegacyVoiceInkProviderValue(transcriptionProviderValue) {
            transcriptionProvider = .localWhisper
            transcriptionModel = RomaTranscriptionModelCatalog.localBaseModel
        } else {
            transcriptionProvider = try container.decode(RomaProviderKind.self, forKey: .transcriptionProvider)
            transcriptionModel = try container.decode(String.self, forKey: .transcriptionModel)
        }

        let postProcessingProviderValue = try container.decode(String.self, forKey: .postProcessingProvider)
        if Self.isLegacyVoiceInkProviderValue(postProcessingProviderValue) {
            isPostProcessingEnabled = false
            postProcessingProvider = .groq
            postProcessingModel = RomaAIModelCatalog.defaultModel(for: .groq)
        } else {
            postProcessingProvider = try container.decode(RomaProviderKind.self, forKey: .postProcessingProvider)
            postProcessingModel = try container.decode(String.self, forKey: .postProcessingModel)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(transcriptionProvider, forKey: .transcriptionProvider)
        try container.encode(transcriptionModel, forKey: .transcriptionModel)
        try container.encode(isPostProcessingEnabled, forKey: .isPostProcessingEnabled)
        try container.encode(postProcessingProvider, forKey: .postProcessingProvider)
        try container.encode(postProcessingModel, forKey: .postProcessingModel)
        try container.encode(promptTemplate, forKey: .promptTemplate)
        try container.encodeIfPresent(selectedPromptId, forKey: .selectedPromptId)
    }

    private static func isLegacyVoiceInkProviderValue(_ value: String) -> Bool {
        value == "VoiceInk" || value == "voiceInk"
    }

    public var effectivePrompt: String {
        promptTemplate.effectivePrompt
    }

    public var effectiveTranscriptionModel: String {
        transcriptionProvider.selectedModel(transcriptionModel, for: .transcription)
    }

    public func effectiveTranscriptionModel(
        additionalLocalWhisperModelNames: [String]
    ) -> String {
        if transcriptionProvider == .localWhisper,
           additionalLocalWhisperModelNames.contains(transcriptionModel) {
            return transcriptionModel
        }
        return effectiveTranscriptionModel
    }

    public var effectivePostProcessingModel: String {
        postProcessingProvider.selectedModel(postProcessingModel, for: .postProcessing)
    }

    public var summaryPresentation: RomaModeSummaryPresentation {
        RomaModeSummaryPresentation(
            title: name,
            transcriptionText: "Transcription: \(effectiveTranscriptionModel)",
            postProcessingText: isPostProcessingEnabled
                ? "Post-processing: \(effectivePostProcessingModel)"
                : nil
        )
    }

    public func formPresentation(isEditing: Bool) -> RomaModeFormPresentation {
        RomaModeFormPresentation.make(
            isEditing: isEditing,
            isPostProcessingEnabled: isPostProcessingEnabled
        )
    }

    public mutating func selectTranscriptionProvider(
        _ provider: RomaProviderKind,
        preferredModel: String? = nil
    ) {
        transcriptionProvider = provider
        if provider == .customCloud, let preferredModel {
            transcriptionModel = preferredModel
            return
        }
        transcriptionModel = provider.selectedModel(transcriptionModel, for: .transcription)
    }

    public mutating func selectPostProcessingProvider(_ provider: RomaProviderKind) {
        postProcessingProvider = provider
        postProcessingModel = provider.selectedModel(postProcessingModel, for: .postProcessing)
    }

    public mutating func setPostProcessingEnabled(
        _ isEnabled: Bool,
        providerAvailability: RomaModeFormProviderAvailability
    ) {
        isPostProcessingEnabled = isEnabled
        repairProviderSelection(providerAvailability: providerAvailability)
    }

    public mutating func repairModelSelection() {
        repairModelSelection(additionalLocalWhisperModelNames: [])
    }

    public mutating func repairModelSelection(
        additionalLocalWhisperModelNames: [String]
    ) {
        transcriptionModel = effectiveTranscriptionModel(
            additionalLocalWhisperModelNames: additionalLocalWhisperModelNames
        )
        postProcessingModel = effectivePostProcessingModel
    }

    public mutating func repairLocalWhisperModelSelection(
        additionalLocalWhisperModelNames: [String]
    ) {
        guard transcriptionProvider == .localWhisper else { return }
        transcriptionModel = effectiveTranscriptionModel(
            additionalLocalWhisperModelNames: additionalLocalWhisperModelNames
        )
    }

    public mutating func repairCustomCloudModelSelection(
        availableModelNames: [String]
    ) {
        guard transcriptionProvider == .customCloud,
              !availableModelNames.contains(transcriptionModel) else { return }
        transcriptionModel = availableModelNames.first ?? ""
    }

    public var runtimeConfiguration: RomaModeRuntimeConfiguration {
        runtimeConfiguration(additionalLocalWhisperModelNames: [])
    }

    public func runtimeConfiguration(
        additionalLocalWhisperModelNames: [String],
        prompts: [RomaCustomPrompt] = [],
        recordingPromptOverrideId: UUID? = nil
    ) -> RomaModeRuntimeConfiguration {
        let prompt = RomaCustomPromptPolicy.activePrompt(
            selectedPromptId: recordingPromptOverrideId ?? selectedPromptId,
            prompts: prompts
        )
        return RomaModeRuntimeConfiguration(
            transcriptionProvider: transcriptionProvider,
            transcriptionModel: effectiveTranscriptionModel(
                additionalLocalWhisperModelNames: additionalLocalWhisperModelNames
            ),
            postProcessingProvider: postProcessingProvider,
            postProcessingModel: effectivePostProcessingModel,
            prompt: prompt?.finalPromptText ?? effectivePrompt,
            promptName: prompt?.title,
            isPostProcessingEnabled: isPostProcessingEnabled
        )
    }

    public mutating func repairProviderSelection(
        availableTranscriptionProviders: [RomaProviderKind],
        availablePostProcessingProviders: [RomaProviderKind]
    ) {
        // NVIDIA cloud backup is explicitly selected; never redirect audio into or out of it.
        if transcriptionProvider != .nvidia,
           !availableTranscriptionProviders.contains(transcriptionProvider),
           let provider = availableTranscriptionProviders.first(where: { $0 != .nvidia }) {
            selectTranscriptionProvider(provider)
        }

        if isPostProcessingEnabled,
           !availablePostProcessingProviders.contains(postProcessingProvider),
           let provider = availablePostProcessingProviders.first {
            selectPostProcessingProvider(provider)
        }

        repairModelSelection()
    }

    public mutating func repairProviderSelection(
        providerAvailability: RomaModeFormProviderAvailability
    ) {
        repairProviderSelection(
            availableTranscriptionProviders: providerAvailability.transcriptionProviders,
            availablePostProcessingProviders: providerAvailability.postProcessingProviders
        )
    }

    public static func defaultLocalWhisper(name: String = "Default") -> Mode {
        Mode(
            name: name,
            transcriptionProvider: .localWhisper,
            transcriptionModel: RomaTranscriptionModelCatalog.localBaseModel,
            isPostProcessingEnabled: false,
            postProcessingProvider: .groq,
            postProcessingModel: RomaProviderKind.groq.defaultModel(for: .postProcessing)
                ?? RomaAIModelCatalog.defaultModel(for: .groq),
            promptTemplate: RomaPostProcessingPromptTemplate(type: .summary)
        )
    }

    public static func defaultModesAndSelection(name: String = "Default") -> (
        modes: [Mode],
        selectedModeId: UUID
    ) {
        let defaultMode = defaultLocalWhisper(name: name)
        return ([defaultMode], defaultMode.id)
    }

    public func isSaveableDraft(
        availableTranscriptionProviders: [RomaProviderKind],
        availablePostProcessingProviders: [RomaProviderKind]
    ) -> Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        guard availableTranscriptionProviders.contains(transcriptionProvider) else {
            return false
        }

        guard !isPostProcessingEnabled || availablePostProcessingProviders.contains(postProcessingProvider) else {
            return false
        }

        if selectedPromptId == nil, promptTemplate.type == .custom {
            return !promptTemplate.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return true
    }

    public func isSaveableDraft(
        providerAvailability: RomaModeFormProviderAvailability
    ) -> Bool {
        isSaveableDraft(
            availableTranscriptionProviders: providerAvailability.transcriptionProviders,
            availablePostProcessingProviders: providerAvailability.postProcessingProviders
        )
    }
}

public extension Collection where Element == Mode {
    func activeMode(selectedModeId: UUID?) -> Mode? {
        if let selectedModeId,
           let selectedMode = first(where: { $0.id == selectedModeId }) {
            return selectedMode
        }

        return first
    }

    func runtimeConfiguration(
        selectedModeId: UUID?,
        additionalLocalWhisperModelNames: [String] = [],
        prompts: [RomaCustomPrompt] = [],
        recordingPromptOverrideId: UUID? = nil
    ) -> RomaModeRuntimeConfiguration {
        activeMode(selectedModeId: selectedModeId)?.runtimeConfiguration(
            additionalLocalWhisperModelNames: additionalLocalWhisperModelNames,
            prompts: prompts,
            recordingPromptOverrideId: recordingPromptOverrideId
        ) ?? .fallback
    }

    func transcriptionLanguages(selectedModeId: UUID?) -> [String: String] {
        guard let provider = activeMode(selectedModeId: selectedModeId)?.transcriptionProvider else {
            return RomaLanguageCatalog.whisperLanguages()
        }

        return RomaLanguageCatalog.languages(for: provider)
    }

    func repairedSelectedTranscriptionLanguage(
        _ language: String?,
        selectedModeId: UUID?
    ) -> String {
        RomaTranscriptionLanguageSupport.validLanguageOrFallback(
            language,
            languages: transcriptionLanguages(selectedModeId: selectedModeId)
        )
    }

    func repairedSelectedModeId(_ selectedModeId: UUID?) -> UUID? {
        guard let selectedModeId,
              contains(where: { $0.id == selectedModeId }) else {
            return first?.id
        }

        return selectedModeId
    }

    var modeSelectionPresentation: RomaModeSelectionPresentation {
        if count > 1 {
            return RomaModeSelectionPresentation(kind: .picker)
        }

        guard let mode = first else {
            return RomaModeSelectionPresentation(kind: .hidden)
        }

        return RomaModeSelectionPresentation(kind: .singleModeName(mode.name))
    }
}
