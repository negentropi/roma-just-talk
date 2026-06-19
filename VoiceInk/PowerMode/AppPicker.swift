import SwiftUI
import VoiceInkCore

struct AppPickerPopover: View {
    let installedApps: [(url: URL, name: String, bundleId: String, icon: NSImage)]
    @Binding var selectedAppConfigs: [VoiceInkPowerModeAppConfig]
    @Binding var searchText: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: VoiceInkPowerModePresentation.appPickerSearchSystemImageName)
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField(VoiceInkPowerModePresentation.appPickerSearchPlaceholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: VoiceInkPowerModePresentation.appPickerClearSearchSystemImageName)
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(installedApps, id: \.bundleId) { app in
                        let isSelected = selectedAppConfigs.containsPowerModeAppConfig(bundleIdentifier: app.bundleId)

                        Button {
                            toggleAppSelection(app)
                        } label: {
                            HStack(spacing: 10) {
                                Image(nsImage: app.icon)
                                    .resizable()
                                    .frame(width: 28, height: 28)
                                    .cornerRadius(6)

                                Text(app.name)
                                    .font(.system(size: 13))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                Spacer()

                                if isSelected {
                                    Image(systemName: VoiceInkPowerModePresentation.appPickerSelectedSystemImageName)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 280, height: 380)
    }

    private func toggleAppSelection(_ app: (url: URL, name: String, bundleId: String, icon: NSImage)) {
        selectedAppConfigs.togglePowerModeAppConfig(bundleIdentifier: app.bundleId, appName: app.name)
    }
}
