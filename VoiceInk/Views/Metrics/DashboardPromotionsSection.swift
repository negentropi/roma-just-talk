import SwiftUI
import AppKit
import VoiceInkCore

struct DashboardPromotionsSection: View {
    let licenseState: LicenseViewModel.LicenseState
    @AppStorage(VoiceInkDashboardPromotionPresentation.affiliateDismissedKey)
    private var isAffiliatePromotionDismissed = VoiceInkDashboardPromotionPresentation.defaultIsAffiliateDismissed

    private var promotionCards: [VoiceInkDashboardPromotionCardPresentation] {
        VoiceInkDashboardPromotionPresentation.cards(
            for: licenseState,
            isAffiliateDismissed: isAffiliatePromotionDismissed
        )
    }
    
    var body: some View {
        if !promotionCards.isEmpty {
            HStack(alignment: .top, spacing: 18) {
                ForEach(promotionCards) { card in
                    DashboardPromotionCard(
                        presentation: card,
                        action: { open(card.actionURL) },
                        onDismiss: card.isDismissible ? dismissAffiliatePromotion : nil
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            EmptyView()
        }
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private func dismissAffiliatePromotion() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isAffiliatePromotionDismissed = true
        }
    }
}

private struct DashboardPromotionCard: View {
    let presentation: VoiceInkDashboardPromotionCardPresentation
    let action: () -> Void
    var onDismiss: (() -> Void)? = nil
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 13) {
                Text(presentation.badgeDisplayText)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
                    .foregroundStyle(.secondary)

                Text(presentation.title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(presentation.message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: action) {
                    HStack(spacing: 6) {
                        Text(presentation.actionTitle)
                        Image(systemName: presentation.actionSystemImageName)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            if let onDismiss = onDismiss, let dismissHelpText = presentation.dismissHelpText {
                Button(action: onDismiss) {
                    Image(systemName: VoiceInkDashboardPromotionPresentation.dismissSystemImageName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(12)
                .help(dismissHelpText)
            }
        }
        .background(CardBackground(isSelected: false, cornerRadius: 22))
    }
}
