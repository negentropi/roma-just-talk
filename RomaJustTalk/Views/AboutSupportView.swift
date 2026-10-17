import SwiftUI
import RomaCore

struct AboutSupportView: View {
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        ?? RomaSystemInformationReport.unknownValueText

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(spacing: 16) {
                    AppIconView()

                    Text(RomaAboutSupportPresentation.productName)
                        .font(.system(size: 32, weight: .bold))

                    Text(RomaAboutSupportPresentation.versionText(appVersion))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(RomaAboutSupportPresentation.subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)

                VStack(alignment: .leading, spacing: 10) {
                    Text(RomaAboutSupportPresentation.resourcesTitle)
                        .font(.headline)

                    ForEach(RomaHelpResourcesPresentation.resources) { resource in
                        Button {
                            open(resource.destination)
                        } label: {
                            HStack {
                                Image(systemName: resource.systemImageName)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 20)

                                Text(resource.title)
                                    .font(.system(size: 13, weight: .semibold))

                                Spacer()

                                Image(systemName: RomaHelpResourcesPresentation.externalLinkSystemImageName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
                .frame(maxWidth: 480)
                .background(CardBackground(isSelected: false))
            }
            .frame(maxWidth: .infinity)
            .padding(32)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func open(_ destination: RomaHelpResourceDestination) {
        switch destination {
        case .url(let url):
            NSWorkspace.shared.open(url)
        case .supportEmail:
            EmailSupport.openSupportEmail()
        }
    }
}
