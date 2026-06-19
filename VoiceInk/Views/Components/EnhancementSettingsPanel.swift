import SwiftUI
import VoiceInkCore

struct EnhancementSettingsPanel: View {
    @EnvironmentObject private var enhancementService: AIEnhancementService
    private let presentation = VoiceInkEnhancementSettingsPresentation.macOS
    @AppStorage(VoiceInkUserDefaultsKey.skipShortEnhancement)
    private var isSkipShortEnhancementEnabled = VoiceInkPreferenceDefault.skipShortEnhancement
    @AppStorage(VoiceInkUserDefaultsKey.shortEnhancementWordThreshold)
    private var shortEnhancementWordThreshold = VoiceInkPreferenceDefault.shortEnhancementWordThreshold
    @AppStorage(VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
    private var enhancementTimeoutSeconds = VoiceInkPreferenceDefault.enhancementTimeoutSeconds
    @AppStorage(VoiceInkUserDefaultsKey.enhancementRetryOnTimeout)
    private var retryOnTimeout = VoiceInkPreferenceDefault.enhancementRetryOnTimeout
    @State private var isShortEnhancementExpanded = false
    @State private var isHandlingToggleChange = false

    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text(presentation.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(presentation.closeButtonHelp)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(
                Divider().opacity(0.5), alignment: .bottom
            )

            // Content
            Form {
                Section {
                    Toggle(isOn: $enhancementService.useClipboardContext) {
                        HStack(spacing: 4) {
                            Text(presentation.clipboardContextTitle)
                            InfoTip(presentation.clipboardContextHelp)
                        }
                    }
                    .toggleStyle(.switch)

                    Toggle(isOn: $enhancementService.useScreenCaptureContext) {
                        HStack(spacing: 4) {
                            Text(presentation.screenContextTitle)
                            InfoTip(presentation.screenContextHelp)
                        }
                    }
                    .toggleStyle(.switch)
                } header: {
                    Text(presentation.contextSectionTitle)
                }

                Section {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Toggle(isOn: Binding(
                                get: { isSkipShortEnhancementEnabled },
                                set: { newValue in
                                    isHandlingToggleChange = true
                                    isSkipShortEnhancementEnabled = newValue
                                    if newValue {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isShortEnhancementExpanded = true
                                        }
                                    } else {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isShortEnhancementExpanded = false
                                        }
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        isHandlingToggleChange = false
                                    }
                                }
                            )) {
                                HStack(spacing: 4) {
                                    Text(presentation.skipShortEnhancementTitle)
                                    InfoTip(presentation.skipShortEnhancementHelp)
                                }
                            }
                            .toggleStyle(.switch)

                            Spacer()

                            Image(systemName: presentation.disclosureSystemImageName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .rotationEffect(.degrees(isSkipShortEnhancementEnabled && isShortEnhancementExpanded ? 90 : 0))
                                .opacity(isSkipShortEnhancementEnabled ? 1 : 0.4)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !isHandlingToggleChange else { return }
                            if isSkipShortEnhancementEnabled {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isShortEnhancementExpanded.toggle()
                                }
                            }
                        }

                        if isSkipShortEnhancementEnabled && isShortEnhancementExpanded {
                            Picker(presentation.minimumWordsPickerTitle, selection: $shortEnhancementWordThreshold) {
                                ForEach(presentation.shortEnhancementWordOptions) { option in
                                    Text(option.title).tag(option.value)
                                }
                            }
                            .padding(.top, 12)
                            .padding(.leading, 4)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: isShortEnhancementExpanded)
                }

                Section {
                    Picker(presentation.timeoutPickerTitle, selection: $enhancementTimeoutSeconds) {
                        ForEach(presentation.timeoutOptions) { option in
                            Text(option.title).tag(option.value)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker(presentation.timeoutRetryPickerTitle, selection: $retryOnTimeout) {
                        ForEach(presentation.timeoutRetryOptions) { option in
                            Text(option.title).tag(option.value)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    HStack(spacing: 4) {
                        Text(presentation.requestTimeoutSectionTitle)
                        InfoTip(presentation.requestTimeoutHelp)
                    }
                }

                Section {
                    EnhancementShortcutsView()
                } header: {
                    Text(presentation.shortcutsSectionTitle)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }
}
