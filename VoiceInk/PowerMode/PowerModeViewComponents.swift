import SwiftUI
import VoiceInkCore

struct VoiceInkButton: View {
    let title: String
    let action: () -> Void
    var isDisabled: Bool = false
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isDisabled ? Color.accentColor.opacity(0.5) : Color.accentColor)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

struct PowerModeEmptyStateView: View {
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Power Modes")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add customized power modes for different contexts")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VoiceInkButton(
                title: "Add New Power Mode",
                action: action
            )
            .frame(maxWidth: 250)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PowerModeConfigurationsGrid: View {
    @ObservedObject var powerModeManager: PowerModeManager
    let onEditConfig: (PowerModeConfig) -> Void
    @EnvironmentObject var enhancementService: AIEnhancementService
    
    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach($powerModeManager.configurations) { $config in
                ConfigurationRow(
                    config: $config,
                    isEditing: false,
                    powerModeManager: powerModeManager,
                    onEditConfig: onEditConfig
                )
            }
        }
    }
}

/// Small, consistent icon-only add button used across Power Mode configuration rows.
struct AddIconButton: View {
    let helpText: String
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 18))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(helpText)
        .disabled(isDisabled)
    }
}

struct ConfigurationRow: View {
    @Binding var config: PowerModeConfig
    let isEditing: Bool
    let powerModeManager: PowerModeManager
    let onEditConfig: (PowerModeConfig) -> Void
    @EnvironmentObject var enhancementService: AIEnhancementService
    @EnvironmentObject var transcriptionModelManager: TranscriptionModelManager
    @State private var isHovering = false
    
    private let maxAppIconsToShow = 5
    
    private var selectedPromptTitle: String? {
        guard let promptId = config.selectedPrompt,
              let uuid = UUID(uuidString: promptId) else { return nil }
        return enhancementService.allPrompts.first { $0.id == uuid }?.title
    }
    
    private var selectedModelDisplayText: String? {
        if let modelName = config.selectedTranscriptionModelName,
           let model = transcriptionModelManager.allAvailableModels.first(where: { $0.name == modelName }) {
            return model.displayName
        }
        return VoiceInkPowerModePresentation.defaultOverrideDisplayText
    }
    
    private var selectedLanguage: String? {
        let languageOptions: [String: String]
        if let modelName = config.selectedTranscriptionModelName,
           let model = transcriptionModelManager.allAvailableModels.first(where: { $0.name == modelName }) {
            languageOptions = model.transcriptionLanguageOptions
        } else {
            languageOptions = [:]
        }

        return VoiceInkPowerModePresentation.selectedLanguageDisplayText(
            selectedLanguage: config.selectedLanguage,
            languageOptions: languageOptions
        )
    }
    
    private var appCount: Int { return config.appConfigs?.count ?? 0 }
    private var websiteCount: Int { return config.urlConfigs?.count ?? 0 }
    
    private var websiteText: String {
        VoiceInkPowerModePresentation.websiteTriggerCountText(websiteCount)
    }
    
    private var appText: String {
        VoiceInkPowerModePresentation.appTriggerCountText(appCount)
    }
    
    private var extraAppsCount: Int {
        return max(0, appCount - maxAppIconsToShow)
    }
    
    private var visibleAppConfigs: [VoiceInkPowerModeAppConfig] {
        return Array(config.appConfigs?.prefix(maxAppIconsToShow) ?? [])
    }

    private var rowDetailPresentation: VoiceInkPowerModeRowDetailPresentation {
        VoiceInkPowerModePresentation.rowDetailPresentation(
            config: config,
            transcriptionModelDisplayText: selectedModelDisplayText,
            selectedLanguageDisplayText: selectedLanguage,
            selectedPromptTitle: selectedPromptTitle
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(NSColor.controlBackgroundColor))
                        .frame(width: 40, height: 40)
                    
                    Text(config.emoji)
                        .font(.system(size: 20))
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(config.name)
                            .font(.system(size: 15, weight: .semibold))
                        
                        if config.isDefault {
                            Text("Default")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor))
                                .foregroundColor(.white)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        if appCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "app.fill")
                                    .font(.system(size: 10))
                                Text(appText)
                                    .font(.caption2)
                            }
                        }

                        if websiteCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "globe")
                                    .font(.system(size: 10))
                                Text(websiteText)
                                    .font(.caption2)
                            }
                        }
                    }
                    .padding(.top, 2)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $config.isEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    .labelsHidden()
                    .onChange(of: config.isEnabled) { _, _ in
                        powerModeManager.updateConfiguration(config)
                    }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            
            if rowDetailPresentation.isVisible {
                Divider()
                
                HStack(spacing: 8) {
                    ForEach(rowDetailPresentation.chips) { chip in
                        PowerModeRowDetailChipView(chip: chip)
                    }

                    Spacer()
                }
                
                .padding(.vertical, 6)
                .padding(.horizontal, 16)
                .background(Color.secondary.opacity(0.1))
            }
    }
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .background(CardBackground(isSelected: isEditing))
    .opacity(config.isEnabled ? 1.0 : 0.5)

    .onHover { hovering in
        withAnimation(.easeInOut(duration: 0.15)) {
            isHovering = hovering
        }
    }
    .onTapGesture(count: 2) {
        onEditConfig(config)
    }
    .contextMenu {
        Button(action: {
            onEditConfig(config)
        }) {
            Label("Edit", systemImage: "pencil")
        }
        Button(role: .destructive, action: {
            let deleteConfirmation = VoiceInkPowerModePresentation.deleteConfirmation(configName: config.name)
            let alert = NSAlert()
            alert.messageText = deleteConfirmation.title
            alert.informativeText = deleteConfirmation.message
            alert.alertStyle = .warning
            alert.addButton(withTitle: deleteConfirmation.primaryButtonTitle)
            alert.addButton(withTitle: deleteConfirmation.cancelButtonTitle)
            alert.buttons[0].hasDestructiveAction = true
            
            if alert.runModal() == .alertFirstButtonReturn {
                powerModeManager.removeConfiguration(with: config.id)
            }
        }) {
            Label("Delete", systemImage: "trash")
        }
    }
    }
    
    private var isSelected: Bool {
        return isEditing
    }
}

private struct PowerModeRowDetailChipView: View {
    let chip: VoiceInkPowerModeRowDetailChipPresentation

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 10))
            Text(chip.text)
                .font(.caption)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule()
            .fill(backgroundColor))
        .overlay {
            if !usesAccentStyle {
                Capsule()
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            }
        }
        .foregroundColor(usesAccentStyle ? .accentColor : .primary)
    }

    private var iconName: String {
        switch chip.kind {
        case .transcriptionModel:
            return "waveform"
        case .selectedLanguage:
            return "globe"
        case .aiModel:
            return "cpu"
        case .autoSend:
            return "keyboard"
        case .contextAwareness:
            return "camera.viewfinder"
        case .prompt:
            return "sparkles"
        }
    }

    private var backgroundColor: Color {
        usesAccentStyle ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor)
    }

    private var usesAccentStyle: Bool {
        chip.kind == .prompt
    }
}

struct PowerModeAppIcon: View {
    let bundleId: String
    
    var body: some View {
        if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appUrl.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)
        }
    }
}

struct AppGridItem: View {
    let app: (url: URL, name: String, bundleId: String, icon: NSImage)
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 40, height: 40)
                    .cornerRadius(8)
                    .shadow(color: Color(NSColor.shadowColor).opacity(0.1), radius: 2, x: 0, y: 1)
                Text(app.name)
                    .font(.system(size: 10))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 28)
            }
            .frame(width: 80, height: 80)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
