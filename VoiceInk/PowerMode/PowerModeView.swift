import SwiftUI
import SwiftData
import VoiceInkCore

struct PowerModeView: View {
    @StateObject private var powerModeManager = PowerModeManager.shared
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @EnvironmentObject private var aiService: AIService
    @State private var activeSheet: PowerModeSheet?

    /// Single sheet route so add/edit/reorder share one native sheet owner and never
    /// race two `.sheet` modifiers. Each configuration presentation gets a fresh ID so
    /// the form's state is rebuilt from the selected mode's payload.
    private enum PowerModeSheet: Identifiable {
        case configuration(VoiceInkPowerModeConfigurationMode, presentationID: UUID)
        case reorder

        var id: String {
            switch self {
            case .configuration(_, let presentationID):
                return "configuration-\(presentationID.uuidString)"
            case .reorder:
                return "reorder"
            }
        }
    }

    var body: some View {
            VStack(spacing: 0) {
                // Header Section
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(VoiceInkPowerModePresentation.panelTitle)
                                    .font(.system(size: 28, weight: .bold, design: .default))
                                    .foregroundColor(.primary)
                                
                                InfoTip(
                                    VoiceInkPowerModePresentation.panelInfoTipText,
                                    learnMoreURL: VoiceInkPowerModePresentation.panelLearnMoreURLString
                                )
                            }
                            
                            Text(VoiceInkPowerModePresentation.panelSubtitle)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Button(action: {
                                openConfiguration(.add)
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: VoiceInkPowerModePresentation.addButtonSystemImageName)
                                        .font(.system(size: 12, weight: .medium))
                                    Text(VoiceInkPowerModeConfigurationMode.add.title)
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.accentColor)
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .accessibilityIdentifier("powerMode.configuration.add")

                            Button(action: { openReorder() }) {
                                HStack(spacing: 6) {
                                    Image(systemName: VoiceInkPowerModePresentation.reorderButtonSystemImageName)
                                        .font(.system(size: 12, weight: .medium))
                                    Text(VoiceInkPowerModePresentation.reorderButtonTitle)
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundColor(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .accessibilityIdentifier("powerMode.reorder.open")
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
                
                // Content Section
                Group {
                        GeometryReader { geometry in
                            ScrollView {
                                VStack(spacing: 0) {
                                    if powerModeManager.configurations.isEmpty {
                                        VStack(spacing: 24) {
                                            Spacer()
                                                .frame(height: geometry.size.height * 0.2)
                                            
                                            VStack(spacing: 16) {
                                                Image(systemName: VoiceInkPowerModePresentation.emptyPanelSystemImageName)
                                                    .font(.system(size: 48, weight: .regular))
                                                    .foregroundColor(.secondary.opacity(0.6))
                                                
                                                VStack(spacing: 8) {
                                                    Text(VoiceInkPowerModePresentation.emptyPanelTitle)
                                                        .font(.system(size: 20, weight: .medium))
                                                        .foregroundColor(.primary)
                                                    
                                                    Text(VoiceInkPowerModePresentation.emptyPanelMessage)
                                                        .font(.system(size: 14))
                                                        .foregroundColor(.secondary)
                                                        .multilineTextAlignment(.center)
                                                        .lineSpacing(2)
                                                }
                                            }
                                            
                                            Spacer()
                                        }
                                        .frame(maxWidth: .infinity)
                                        .frame(minHeight: geometry.size.height)
                                    } else {
                                        VStack(spacing: 0) {
                                            PowerModeConfigurationsGrid(
                                                powerModeManager: powerModeManager,
                                                onEditConfig: { config in
                                                    openConfiguration(.edit(config))
                                                }
                                            )
                                            .padding(.horizontal, 24)
                                            .padding(.vertical, 20)
                                            
                                            Spacer()
                                                .frame(height: 40)
                                        }
                                    }
                                }
                            }
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
            }
            .background(Color(NSColor.controlBackgroundColor))
            .settingsSheet(item: $activeSheet, width: 400) { sheet in
                switch sheet {
                case .configuration(let mode, let presentationID):
                    ConfigurationView(mode: mode, powerModeManager: powerModeManager, onDismiss: dismissSheet)
                        .id(presentationID)
                case .reorder:
                    ReorderPanelView(powerModeManager: powerModeManager, onDismiss: dismissSheet)
                }
            }
    }

    private func openConfiguration(_ mode: VoiceInkPowerModeConfigurationMode) {
        activeSheet = .configuration(mode, presentationID: UUID())
    }

    private func openReorder() {
        activeSheet = .reorder
    }

    private func dismissSheet() {
        activeSheet = nil
    }
}

struct ReorderPanelView: View {
    @ObservedObject var powerModeManager: PowerModeManager
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text(VoiceInkPowerModePresentation.reorderPanelTitle)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: VoiceInkPowerModePresentation.reorderPanelCloseSystemImageName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(VoiceInkPowerModePresentation.reorderPanelCloseHelpText)
                .accessibilityLabel(Text(VoiceInkPowerModePresentation.reorderPanelCloseHelpText))
                .accessibilityIdentifier("powerMode.reorder.close")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(Divider().opacity(0.5), alignment: .bottom)

            // Reorder list
            List {
                ForEach(powerModeManager.configurations) { config in
                    HStack(spacing: 12) {
                        Image(systemName: VoiceInkPowerModePresentation.reorderHandleSystemImageName)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)

                        ZStack {
                            Circle()
                                .fill(Color(NSColor.controlBackgroundColor))
                                .frame(width: 36, height: 36)
                            Text(config.emoji)
                                .font(.system(size: 18))
                        }

                        Text(config.name)
                            .font(.system(size: 14, weight: .medium))

                        Spacer()

                        HStack(spacing: 6) {
                            if config.isDefault {
                                Text(VoiceInkPowerModePresentation.defaultBadgeTitle)
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.accentColor))
                                    .foregroundColor(.white)
                            }
                            if !config.isEnabled {
                                Text(VoiceInkPowerModePresentation.disabledBadgeTitle)
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color(NSColor.controlBackgroundColor)))
                                    .overlay(
                                        Capsule().stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                                    )
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .onMove(perform: powerModeManager.moveConfigurations)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .padding(.top, 8)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}


struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 16, weight: .bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
    }
}
