import SwiftUI
import SwiftData
import OSLog
import RomaCore

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}

struct ContentView: View {
    private let logger = Logger(subsystem: RomaAppIdentity.loggingSubsystem, category: "ContentView")
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var engine: RomaEngine
    @EnvironmentObject private var whisperModelManager: WhisperModelManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @AppStorage(RomaUserDefaultsKey.powerModeUIFlag) private var powerModeUIFlag = RomaPreferenceDefault.powerModeUIEnabled
    @State private var selectedView: RomaMacOSMainViewItem? = RomaMacOSMainViewItem.defaultSelection
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

    private var visibleViewTypes: [RomaMacOSMainViewItem] {
        RomaMacOSMainViewItem.visibleItems(powerModeEnabled: powerModeUIFlag)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedView) {
                Section {
                    HStack(spacing: 10) {
                        if let appIcon = NSImage(named: "AppIcon") {
                            Image(nsImage: appIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 30, height: 30)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(RomaAppIdentity.compactDisplayName)
                                .font(.system(size: 14, weight: .semibold))

                            Text(RomaAppIdentity.sidebarSubtitle)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .listRowInsets(EdgeInsets(top: 2, leading: 2, bottom: 8, trailing: 8))
                    .listRowSeparator(.hidden)
                }

                ForEach(visibleViewTypes) { viewType in
                    Section {
                        NavigationLink(value: viewType) {
                            SidebarItemView(viewType: viewType)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .navigationTitle(RomaAppIdentity.compactDisplayName)
            .navigationSplitViewColumnWidth(210)
        } detail: {
            if let selectedView = selectedView {
                detailView(for: selectedView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(selectedView.title)
            } else {
                Text(RomaMacOSMainViewItem.emptySelectionTitle)
                    .foregroundColor(.secondary)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 950)
        .onAppear {
            logger.notice("ContentView appeared")
        }
        .onDisappear {
            logger.notice("ContentView disappeared")
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToDestination)) { notification in
            if let destination = RomaMacOSNavigationRequest.destination(from: notification) {
                logger.notice("navigateToDestination received: \(destination, privacy: .public)")
                if let viewItem = RomaMacOSMainViewItem.item(forNavigationDestination: destination) {
                    selectedView = viewItem
                }
            }
        }
    }
    
    @ViewBuilder
    private func detailView(for viewType: RomaMacOSMainViewItem) -> some View {
        switch viewType {
        case .metrics:
            MetricsView()
        case .models:
            ModelManagementView()
        case .enhancement:
            EnhancementSettingsView()
        case .transcribeAudio:
            AudioTranscribeView()
        case .history:
            InlineHistoryView()
        case .audioInput:
            AudioInputSettingsView()
        case .dictionary:
            DictionarySettingsView()
        case .powerMode:
            PowerModeView()
        case .settings:
            SettingsView()
        case .about:
            AboutSupportView()
        case .permissions:
            PermissionsView()
        }
    }
}

private struct SidebarItemView: View {
    let viewType: RomaMacOSMainViewItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: viewType.systemImageName)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 24, height: 24)

            Text(viewType.title)
                .font(.system(size: 14, weight: .medium))

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
    }
}
