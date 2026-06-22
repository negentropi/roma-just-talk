import SwiftUI
import SwiftData
import Charts
import VoiceInkCore

struct MetricsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @StateObject private var licenseViewModel = LicenseViewModel()
    
    var body: some View {
        VStack {
            if let trialBanner = VoiceInkLicenseTrialBannerPresentation.banner(
                for: licenseViewModel.licenseState
            ) {
                TrialMessageView(
                    presentation: trialBanner,
                    onAddLicenseKey: navigateToLicense
                )
                .padding()
            }

            MetricsContent(
                modelContext: modelContext,
                licenseState: licenseViewModel.licenseState
            )
        }
        .background(Color(.windowBackgroundColor))
    }

    private func navigateToLicense() {
        NotificationCenter.default.post(
            name: .navigateToDestination,
            object: nil,
            userInfo: VoiceInkMacOSNavigationRequest.userInfo(destination: .license)
        )
    }
}
