import SwiftUI
import VoiceInkCore

struct LicenseManagementView: View {
    @StateObject private var licenseViewModel = LicenseViewModel()
    @Environment(\.colorScheme) private var colorScheme
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        ?? VoiceInkLicenseManagementPresentation.appVersionFallback
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero Section
                heroSection
                
                // Main Content
                VStack(spacing: 32) {
                    if case .licensed = licenseViewModel.licenseState {
                        activatedContent
                    } else {
                        purchaseContent
                    }
                }
                .padding(32)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var heroSection: some View {
        VStack(spacing: 24) {
            // App Icon
            AppIconView()
            
            // Title Section
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    Image(systemName: VoiceInkLicenseManagementPresentation.heroSystemImageName)
                        .font(.system(size: 32))
                        .foregroundStyle(.blue)
                    
                    HStack(alignment: .lastTextBaseline, spacing: 8) { 
                        Text(VoiceInkLicenseManagementPresentation.heroTitle(for: licenseViewModel.licenseState))
                            .font(.system(size: 32, weight: .bold))
                        
                        Text(VoiceInkLicenseManagementPresentation.appVersionText(appVersion))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 4)
                    }
                }
                
                Text(VoiceInkLicenseManagementPresentation.heroSubtitle(for: licenseViewModel.licenseState))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if case .licensed = licenseViewModel.licenseState {
                    HStack(spacing: 40) {
                        ForEach(VoiceInkLicenseManagementPresentation.licensedResourceLinks, id: \.id) { resource in
                            Button {
                                openResource(resource)
                            } label: {
                                if resource.id == .tipJar {
                                    animatedTipJarItem(resource)
                                } else {
                                    featureItem(
                                        icon: resource.systemImageName,
                                        title: resource.title,
                                        color: resourceColor(for: resource.id)
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(.vertical, 60)
    }
    
    private var purchaseContent: some View {
        VStack(spacing: 40) {
            // Purchase Card
            VStack(spacing: 24) {
                // Lifetime Access Badge
                HStack {
                    Image(systemName: VoiceInkLicenseManagementPresentation.lifetimeBadgeSystemImageName)
                        .font(.system(size: 20))
                        .foregroundStyle(.blue)
                    Text(VoiceInkLicenseManagementPresentation.lifetimeBadgeTitle)
                        .font(.headline)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
                
                // Purchase Button 
                Button(action: {
                    NSWorkspace.shared.open(VoiceInkLicenseLinks.purchaseURL)
                }) {
                    Text(VoiceInkLicenseManagementPresentation.purchaseButtonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                
                // Features Grid
                HStack(spacing: 40) {
                    ForEach(Array(VoiceInkLicenseManagementPresentation.purchaseFeatures.enumerated()), id: \.offset) { index, feature in
                        featureItem(
                            icon: feature.systemImageName,
                            title: feature.title,
                            color: purchaseFeatureColor(at: index)
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(32)
            .background(CardBackground(isSelected: false))
            .shadow(color: .black.opacity(0.05), radius: 10)

            // License Activation
            VStack(spacing: 20) {
                Text(VoiceInkLicenseManagementPresentation.activationSectionTitle)
                    .font(.headline)
                
                HStack(spacing: 12) {
                    TextField(VoiceInkLicenseManagementPresentation.licenseKeyPlaceholder, text: $licenseViewModel.licenseKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .textCase(.uppercase)
                    
                    Button(action: {
                        Task { await licenseViewModel.validateLicense() }
                    }) {
                        if licenseViewModel.isValidating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(VoiceInkLicenseManagementPresentation.activateButtonTitle)
                                .frame(width: 80)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(licenseViewModel.isValidating)
                }
                
                if let message = licenseViewModel.validationMessage {
                    Text(message)
                        .foregroundColor(licenseViewModel.validationSuccess ? .green : .red)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(32)
            .background(CardBackground(isSelected: false))
            .shadow(color: .black.opacity(0.05), radius: 10)
            
            // Already Purchased Section
            VStack(spacing: 20) {
                Text(VoiceInkLicenseManagementPresentation.existingLicenseSectionTitle)
                    .font(.headline)

                HStack(spacing: 12) {
                    Text(VoiceInkLicenseManagementPresentation.existingLicenseDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: {
                        NSWorkspace.shared.open(VoiceInkLicenseLinks.managementPortalURL)
                    }) {
                        Text(VoiceInkLicenseManagementPresentation.managementPortalButtonTitle)
                            .frame(width: 180)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(32)
            .background(CardBackground(isSelected: false))
            .shadow(color: .black.opacity(0.05), radius: 10)
        }
    }
    
    private var activatedContent: some View {
        VStack(spacing: 32) {
            // Status Card
            VStack(spacing: 24) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.green)
                    Text(VoiceInkLicenseManagementPresentation.activeLicenseTitle)
                        .font(.headline)
                    Spacer()
                    Text(VoiceInkLicenseManagementPresentation.activeLicenseBadgeText)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.green))
                        .foregroundStyle(.white)
                }
                
                Divider()
                
                Text(VoiceInkLicenseManagementPresentation.activeLicenseDeviceLimitText(
                    activationsLimit: licenseViewModel.activationsLimit
                ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .background(CardBackground(isSelected: false))
            .shadow(color: .black.opacity(0.05), radius: 10)
            
            // Deactivation Card
            VStack(alignment: .leading, spacing: 16) {
                Text(VoiceInkLicenseManagementPresentation.deactivationSectionTitle)
                    .font(.headline)

                Button(role: .destructive, action: {
                    licenseViewModel.removeLicense()
                }) {
                    Label(
                        VoiceInkLicenseManagementPresentation.deactivateButtonTitle,
                        systemImage: VoiceInkLicenseManagementPresentation.deactivateSystemImageName
                    )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }
            .padding(32)
            .background(CardBackground(isSelected: false))
            .shadow(color: .black.opacity(0.05), radius: 10)
        }
    }
    
    private func featureItem(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
            
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
    }

    private func openResource(_ resource: VoiceInkLicenseManagementResourceLink) {
        if resource.id == .emailSupport {
            EmailSupport.openSupportEmail()
            return
        }

        guard let urlString = resource.urlString, let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func resourceColor(for resourceID: VoiceInkLicenseManagementResourceID) -> Color {
        switch resourceID {
        case .changelog:
            return .blue
        case .discord:
            return .purple
        case .emailSupport:
            return .orange
        case .docs:
            return .indigo
        case .tipJar:
            return .pink
        }
    }

    private func purchaseFeatureColor(at index: Int) -> Color {
        switch index {
        case 0:
            return .purple
        case 1:
            return .blue
        case 2:
            return .green
        default:
            return .orange
        }
    }
    
    @State private var heartPulse = false
    
    private func animatedTipJarItem(_ resource: VoiceInkLicenseManagementResourceLink) -> some View {
        HStack(spacing: 8) {
            Image(systemName: resource.systemImageName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(resourceColor(for: resource.id))
                .scaleEffect(heartPulse ? 1.3 : 1.0)
                .animation(
                    Animation.easeInOut(duration: 1.2)
                        .repeatForever(autoreverses: true),
                    value: heartPulse
                )
                .onAppear {
                    heartPulse = true
                }
            
            Text(resource.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
    }
}
