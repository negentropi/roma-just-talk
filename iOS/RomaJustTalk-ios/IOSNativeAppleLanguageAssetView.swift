import SwiftUI
import RomaCore

struct IOSNativeAppleLanguageAssetView: View {
    let localeIdentifier: String

    @State private var state: RomaNativeAppleLanguageAssetState = .checking

    var body: some View {
        let presentation = RomaNativeAppleLanguageAssetPresentation.presentation(for: state)

        HStack {
            Text(RomaLanguageCatalog.nativeAppleDisplayName(for: localeIdentifier))
            Spacer()

            switch presentation.display {
            case .hidden:
                EmptyView()
            case .progress:
                ProgressView()
            case .actionButton(let systemImageName):
                Button {
                    downloadAsset()
                } label: {
                    Image(systemName: systemImageName)
                }
                .accessibilityLabel(presentation.accessibilityLabel ?? "Download language")
            case .statusIcon(let systemImageName):
                Image(systemName: systemImageName)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(presentation.helpText ?? "Language status")
            }
        }
        .task(id: localeIdentifier) {
            state = .checking
            state = await IOSNativeAppleSpeechRuntime.assetState(for: localeIdentifier)
        }
    }

    private func downloadAsset() {
        state = .downloading
        Task {
            state = await IOSNativeAppleSpeechRuntime.installAsset(for: localeIdentifier)
        }
    }
}
