import Foundation

public struct VoiceInkModeRuntimeConfiguration: Equatable, Sendable {
    public let transcriptionProvider: VoiceInkProviderKind
    public let transcriptionModel: String
    public let postProcessingProvider: VoiceInkProviderKind
    public let postProcessingModel: String
    public let prompt: String
    public let isPostProcessingEnabled: Bool

    public static var fallback: VoiceInkModeRuntimeConfiguration {
        Mode.defaultLocalWhisper().runtimeConfiguration
    }
}

public enum VoiceInkModeSelectionPresentation: Equatable, Sendable {
    case hidden
    case singleModeName(String)
    case picker

    public static let controlTitle = "Mode"
}

public struct VoiceInkModeSummaryPresentation: Equatable, Sendable {
    public let title: String
    public let transcriptionText: String
    public let postProcessingText: String?
}

public struct VoiceInkModeFormPresentation: Equatable, Sendable {
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
        VoiceInkModeFormPresentation(
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

public struct VoiceInkModeListRepairPlan {
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

public enum VoiceInkModeListPolicy {
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

    public static func defaultModeRepairPlan(
        modes: [Mode],
        selectedModeId: UUID?
    ) -> VoiceInkModeListRepairPlan {
        guard !modes.isEmpty else {
            let defaultSelection = Mode.defaultModesAndSelection()
            return VoiceInkModeListRepairPlan(
                modes: defaultSelection.modes,
                selectedModeId: defaultSelection.selectedModeId,
                shouldReplaceModes: true
            )
        }

        return VoiceInkModeListRepairPlan(
            modes: modes,
            selectedModeId: modes.repairedSelectedModeId(selectedModeId),
            shouldReplaceModes: false
        )
    }
}

public struct Mode: Identifiable, Codable {
    public let id: UUID
    public var name: String

    public var transcriptionProvider: VoiceInkProviderKind
    public var transcriptionModel: String

    public var isPostProcessingEnabled: Bool
    public var postProcessingProvider: VoiceInkProviderKind
    public var postProcessingModel: String
    public var promptTemplate: VoiceInkPostProcessingPromptTemplate

    public init(
        name: String,
        transcriptionProvider: VoiceInkProviderKind = .groq,
        transcriptionModel: String? = nil,
        isPostProcessingEnabled: Bool = false,
        postProcessingProvider: VoiceInkProviderKind = .groq,
        postProcessingModel: String? = nil,
        promptTemplate: VoiceInkPostProcessingPromptTemplate? = nil
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
            ?? VoiceInkAIModelCatalog.defaultModel(for: .groq)
        self.promptTemplate = promptTemplate ?? VoiceInkPostProcessingPromptTemplate(type: .summary)
    }

    public var effectivePrompt: String {
        promptTemplate.effectivePrompt
    }

    public var effectiveTranscriptionModel: String {
        transcriptionProvider.selectedModel(transcriptionModel, for: .transcription)
    }

    public var effectivePostProcessingModel: String {
        postProcessingProvider.selectedModel(postProcessingModel, for: .postProcessing)
    }

    public var summaryPresentation: VoiceInkModeSummaryPresentation {
        VoiceInkModeSummaryPresentation(
            title: name,
            transcriptionText: "Transcription: \(effectiveTranscriptionModel)",
            postProcessingText: isPostProcessingEnabled
                ? "Post-processing: \(effectivePostProcessingModel)"
                : nil
        )
    }

    public func formPresentation(isEditing: Bool) -> VoiceInkModeFormPresentation {
        VoiceInkModeFormPresentation.make(
            isEditing: isEditing,
            isPostProcessingEnabled: isPostProcessingEnabled
        )
    }

    public mutating func selectTranscriptionProvider(_ provider: VoiceInkProviderKind) {
        transcriptionProvider = provider
        transcriptionModel = provider.selectedModel(transcriptionModel, for: .transcription)
    }

    public mutating func selectPostProcessingProvider(_ provider: VoiceInkProviderKind) {
        postProcessingProvider = provider
        postProcessingModel = provider.selectedModel(postProcessingModel, for: .postProcessing)
    }

    public mutating func repairModelSelection() {
        transcriptionModel = effectiveTranscriptionModel
        postProcessingModel = effectivePostProcessingModel
    }

    public var runtimeConfiguration: VoiceInkModeRuntimeConfiguration {
        VoiceInkModeRuntimeConfiguration(
            transcriptionProvider: transcriptionProvider,
            transcriptionModel: effectiveTranscriptionModel,
            postProcessingProvider: postProcessingProvider,
            postProcessingModel: effectivePostProcessingModel,
            prompt: effectivePrompt,
            isPostProcessingEnabled: isPostProcessingEnabled
        )
    }

    public mutating func repairProviderSelection(
        availableTranscriptionProviders: [VoiceInkProviderKind],
        availablePostProcessingProviders: [VoiceInkProviderKind]
    ) {
        if !availableTranscriptionProviders.contains(transcriptionProvider),
           let provider = availableTranscriptionProviders.first {
            selectTranscriptionProvider(provider)
        }

        if isPostProcessingEnabled,
           !availablePostProcessingProviders.contains(postProcessingProvider),
           let provider = availablePostProcessingProviders.first {
            selectPostProcessingProvider(provider)
        }

        repairModelSelection()
    }

    public static func defaultLocalWhisper(name: String = "Default") -> Mode {
        Mode(
            name: name,
            transcriptionProvider: .localWhisper,
            transcriptionModel: VoiceInkTranscriptionModelCatalog.localBaseModel,
            isPostProcessingEnabled: false,
            postProcessingProvider: .groq,
            postProcessingModel: VoiceInkProviderKind.groq.defaultModel(for: .postProcessing)
                ?? VoiceInkAIModelCatalog.defaultModel(for: .groq),
            promptTemplate: VoiceInkPostProcessingPromptTemplate(type: .summary)
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
        availableTranscriptionProviders: [VoiceInkProviderKind],
        availablePostProcessingProviders: [VoiceInkProviderKind]
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

        if promptTemplate.type == .custom {
            return !promptTemplate.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return true
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

    func runtimeConfiguration(selectedModeId: UUID?) -> VoiceInkModeRuntimeConfiguration {
        activeMode(selectedModeId: selectedModeId)?.runtimeConfiguration ?? .fallback
    }

    func transcriptionLanguages(selectedModeId: UUID?) -> [String: String] {
        guard let provider = activeMode(selectedModeId: selectedModeId)?.transcriptionProvider else {
            return VoiceInkLanguageCatalog.whisperLanguages()
        }

        return VoiceInkLanguageCatalog.languages(for: provider)
    }

    func repairedSelectedTranscriptionLanguage(
        _ language: String?,
        selectedModeId: UUID?
    ) -> String {
        VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
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

    var modeSelectionPresentation: VoiceInkModeSelectionPresentation {
        if count > 1 {
            return .picker
        }

        guard let mode = first else {
            return .hidden
        }

        return .singleModeName(mode.name)
    }
}
