import SwiftUI
import VoiceInkCore

// Define a display mode for flexible usage
enum LanguageDisplayMode {
    case full // For settings page with descriptions
    case menuItem // For menu bar with compact layout
}

struct LanguageSelectionView: View {
    @ObservedObject var transcriptionModelManager: TranscriptionModelManager
    @AppStorage(VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
    private var selectedLanguage = VoiceInkDefaultSettings.macOS.selectedTranscriptionLanguage
    // Add display mode parameter with full as the default
    var displayMode: LanguageDisplayMode = .full
    @ObservedObject var whisperPrompt: WhisperPrompt

    private func updateLanguage(_ language: String) {
        guard selectedLanguage != language else { return }

        // Update UI state - the UserDefaults updating is now automatic with @AppStorage
        selectedLanguage = language

        // Force the prompt to update for the new language
        whisperPrompt.updateTranscriptionPrompt()

        // Post notification for language change
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    private var languageSelectionFacts: VoiceInkTranscriptionLanguageSelectionFacts? {
        transcriptionModelManager.currentTranscriptionModel?.transcriptionLanguageSelectionFacts
    }

    private func useCompatibleLanguageForCurrentModel() {
        guard let facts = languageSelectionFacts else { return }
        updateLanguage(facts.compatibleLanguage(selectedLanguage))
    }

    private var nativeAppleAssetControl: some View {
        NativeAppleLanguageAssetControl(
            localeIdentifier: selectedLanguage,
            isVisible: true
        )
        .layoutPriority(1)
    }

    private var englishOnlyMenuButton: some View {
        Button {
            // Do nothing, just showing info
        } label: {
            Text(VoiceInkTranscriptionLanguagePresentation.englishOnlyMenuLabel)
                .foregroundColor(.secondary)
        }
        .disabled(true)
        .onAppear {
            updateLanguage("en")
        }
    }

    var body: some View {
        Group {
            switch displayMode {
            case .full:
                fullView
            case .menuItem:
                menuItemView
            }
        }
        .onAppear {
            useCompatibleLanguageForCurrentModel()
        }
        .onChange(of: transcriptionModelManager.currentTranscriptionModel?.name) { _, _ in
            useCompatibleLanguageForCurrentModel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AppSettingsDidChange)) { _ in
            useCompatibleLanguageForCurrentModel()
        }
    }

    // The original full view layout for settings page
    private var fullView: some View {
        VStack(alignment: .leading, spacing: 16) {
            languageSelectionSection
        }
    }
    
    private var languageSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(VoiceInkTranscriptionLanguagePresentation.sectionTitle)
                .font(.headline)

            if let facts = languageSelectionFacts {
                switch facts.control {
                case .disabledAutodetect:
                    VStack(alignment: .leading, spacing: 8) {
                        Text(VoiceInkTranscriptionLanguagePresentation.autoDetectedLabel)
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Text(VoiceInkTranscriptionLanguagePresentation.autoDetectedDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .disabled(true)
                case .picker:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Picker(
                                VoiceInkTranscriptionLanguagePresentation.menuPickerTitle,
                                selection: Binding(
                                    get: { selectedLanguage },
                                    set: { updateLanguage($0) }
                                )
                            ) {
                                ForEach(
                                    VoiceInkLanguageCatalog.sortedOptions(facts.languageOptions)
                                ) { option in
                                    Text(option.name).tag(option.code)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(maxWidth: facts.showsNativeAppleAssetControl ? 280 : .infinity, alignment: .leading)

                            if facts.showsNativeAppleAssetControl {
                                nativeAppleAssetControl
                            }
                        }

                        Text(
                            VoiceInkTranscriptionLanguagePresentation.multilingualDescription
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                case .hiddenDefault:
                    // For English-only models, force set language to English
                    VStack(alignment: .leading, spacing: 8) {
                        Text(VoiceInkTranscriptionLanguagePresentation.englishOnlyLabel)
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Text(
                            VoiceInkTranscriptionLanguagePresentation.englishOnlyDescription
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .onAppear {
                        // Ensure English is set when viewing English-only model
                        updateLanguage("en")
                    }
                }
            } else {
                Text(VoiceInkModelManagementPresentation.noModelSelectedText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // New compact view for menu bar
    private var menuItemView: some View {
        Group {
            if let facts = languageSelectionFacts {
                switch facts.control {
                case .disabledAutodetect:
                    Button {
                        // Do nothing, just showing info
                    } label: {
                        Text(VoiceInkTranscriptionLanguagePresentation.autoDetectedLabel)
                            .foregroundColor(.secondary)
                    }
                    .disabled(true)
                case .picker:
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(
                                VoiceInkLanguageCatalog.sortedOptions(facts.languageOptions)
                            ) { option in
                                Button {
                                    updateLanguage(option.code)
                                } label: {
                                    HStack {
                                        Text(option.name)
                                        if selectedLanguage == option.code {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(
                                    VoiceInkTranscriptionLanguagePresentation.menuLabel(
                                        selectedLanguage: selectedLanguage,
                                        languages: facts.languageOptions
                                    )
                                )
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10))
                            }
                        }

                        if facts.showsNativeAppleAssetControl {
                            nativeAppleAssetControl
                        }
                    }
                case .hiddenDefault:
                    englishOnlyMenuButton
                }
            } else {
                englishOnlyMenuButton
            }
        }
    }
}
