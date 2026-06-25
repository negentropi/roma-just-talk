import SwiftUI
import SwiftData
import Foundation
import os
import VoiceInkCore

private final class DashboardMetricsCache: @unchecked Sendable {
    static let shared = DashboardMetricsCache()

    private let lock = NSLock()
    private var summary: VoiceInkDashboardMetricsSummary?

    private init() {}

    func currentSummary() -> VoiceInkDashboardMetricsSummary? {
        lock.lock()
        defer { lock.unlock() }
        return summary
    }

    func update(_ summary: VoiceInkDashboardMetricsSummary) {
        lock.lock()
        self.summary = summary
        lock.unlock()
    }
}

private enum DashboardMetricsLoader {
    static func load(from modelContainer: ModelContainer) async throws -> VoiceInkDashboardMetricsSummary {
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()

            let backgroundContext = ModelContext(modelContainer)
            let count = try backgroundContext.fetchCount(FetchDescriptor<SessionMetric>())

            try Task.checkCancellation()

            var descriptor = FetchDescriptor<SessionMetric>()
            descriptor.propertiesToFetch = [\.wordCount, \.audioDuration]

            var accumulator = VoiceInkDashboardMetricsAccumulator()

            try backgroundContext.enumerate(descriptor) { metric in
                accumulator.add(metric)
            }

            try Task.checkCancellation()

            return accumulator.summary(totalCount: count)
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

struct MetricsContent: View {
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "MetricsContent")
    @Environment(\.colorScheme) private var colorScheme
    let modelContext: ModelContext
    let licenseState: LicenseViewModel.LicenseState

    @State private var totalCount: Int = 0
    @State private var totalWords: Int = 0
    @State private var totalDuration: TimeInterval = 0
    @State private var hasLoadedMetricsSnapshot: Bool = false
    @State private var metricsTask: Task<Void, Never>?
    @State private var isModelStatsPanelPresented = false
    @State private var isAccessibilityEnabled = AXIsProcessTrusted()

    init(modelContext: ModelContext, licenseState: LicenseViewModel.LicenseState) {
        self.modelContext = modelContext
        self.licenseState = licenseState

        let cachedSummary = DashboardMetricsCache.shared.currentSummary()
        _totalCount = State(initialValue: cachedSummary?.totalCount ?? 0)
        _totalWords = State(initialValue: cachedSummary?.totalWords ?? 0)
        _totalDuration = State(initialValue: cachedSummary?.totalDuration ?? 0)
        _hasLoadedMetricsSnapshot = State(initialValue: cachedSummary != nil)
    }

    var body: some View {
        Group {
            if totalCount == 0 && hasLoadedMetricsSnapshot {
                emptyStateView
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: 24) {
                            if !isAccessibilityEnabled {
                                accessibilityPermissionCallout
                            }

                            heroSection
                            metricsSection
                            HStack(alignment: .top, spacing: 16) {
                                HelpAndResourcesSection()
                                DashboardPromotionsSection(licenseState: licenseState)
                            }

                            Spacer(minLength: 20)

                            HStack {
                                Spacer()
                                footerActionsView
                            }
                        }
                        .frame(minHeight: geometry.size.height - 56)
                        .padding(.vertical, 28)
                        .padding(.horizontal, 32)
                    }
                    .background(dashboardBackground)
                }
            }
        }
        .task {
            await loadMetricsEfficiently()
        }
        .onAppear(perform: refreshAccessibilityStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionMetricsDidChange)) { _ in
            metricsTask?.cancel()
            metricsTask = Task {
                await loadMetricsEfficiently()
            }
        }
        .onDisappear {
            metricsTask?.cancel()
        }
        .overlay {
            Color.black.opacity(isModelStatsPanelPresented ? 0.1 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(isModelStatsPanelPresented)
                .onTapGesture {
                    withAnimation(.smooth(duration: 0.3)) { isModelStatsPanelPresented = false }
                }
                .animation(.smooth(duration: 0.3), value: isModelStatsPanelPresented)
        }
        .overlay(alignment: .trailing) {
            if isModelStatsPanelPresented {
                ModelPerformancePanel {
                    withAnimation(.smooth(duration: 0.3)) { isModelStatsPanelPresented = false }
                }
                .frame(width: 400)
                .frame(maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color(NSColor.separatorColor)).frame(width: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 8, x: -2, y: 0)
                .ignoresSafeArea()
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.smooth(duration: 0.3), value: isModelStatsPanelPresented)
    }

    private var accessibilityPermissionCallout: some View {
        PermissionCard(
            icon: "hand.raised",
            title: "Accessibility Access",
            description: "VoiceInk needs Accessibility permission to work reliably across your entire Mac",
            isGranted: isAccessibilityEnabled,
            buttonTitle: "Open System Settings",
            buttonAction: grantAccessibilityPermission,
            checkPermission: refreshAccessibilityStatus,
            infoTipMessage: "VoiceInk uses Accessibility to work reliably across apps."
        )
    }

    private func refreshAccessibilityStatus() {
        isAccessibilityEnabled = AXIsProcessTrusted()
    }

    private func grantAccessibilityPermission() {
        PermissionGrantCoordinator.grantAccessibility { granted in
            isAccessibilityEnabled = granted
        }
        refreshAccessibilityStatus()
    }
    
    private func loadMetricsEfficiently() async {
        do {
            let summary = try await DashboardMetricsLoader.load(from: modelContext.container)

            guard !Task.isCancelled else {
                return
            }

            let shouldAcceptSummary = summary.totalCount > 0 || !SessionMetricMigrationService.shared.isRunning

            await MainActor.run {
                guard shouldAcceptSummary else {
                    return
                }

                self.totalCount = summary.totalCount
                self.totalWords = summary.totalWords
                self.totalDuration = summary.totalDuration
                DashboardMetricsCache.shared.update(summary)
                self.hasLoadedMetricsSnapshot = true
            }
        } catch is CancellationError {
        } catch {
            logger.error("Error loading metrics: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var emptyStateView: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    if !isAccessibilityEnabled {
                        accessibilityPermissionCallout
                    }

                    VStack(spacing: 20) {
                        Image(systemName: VoiceInkDashboardPresentation.emptyStateSystemImageName)
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(VoiceInkDashboardPresentation.emptyStateTitle)
                            .font(.title3.weight(.semibold))
                        Text(VoiceInkDashboardPresentation.emptyStateMessage)
                            .foregroundColor(.secondary)
                    }
                    .padding(34)
                    .frame(maxWidth: 420)
                    .background(CardBackground(isSelected: false, cornerRadius: 22))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height - 56)
                }
                .padding(.vertical, 28)
                .padding(.horizontal, 32)
            }
            .background(dashboardBackground)
        }
    }
    
    // MARK: - Sections
    
    private var heroSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 24) {
                heroCopy
                Spacer(minLength: 16)
                heroStatBlock
            }

            VStack(alignment: .leading, spacing: 22) {
                heroCopy
                heroStatBlock
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(CardBackground(isSelected: true, cornerRadius: 24))
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(VoiceInkDashboardPresentation.heroSectionTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)

            Text(VoiceInkDashboardPresentation.heroTitle(
                isSnapshotLoaded: hasLoadedMetricsSnapshot,
                timeSaved: timeSaved
            ))
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(heroSubtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    private var heroStatBlock: some View {
        let heroPills = VoiceInkDashboardPresentation.heroPills(
            isSnapshotLoaded: hasLoadedMetricsSnapshot,
            summary: dashboardMetrics.summary
        )

        HStack(spacing: 10) {
            ForEach(heroPills) { pill in
                heroPill(title: pill.title, value: pill.value)
            }
        }
        .frame(maxWidth: 280, alignment: .trailing)
    }

    private func heroPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 112, alignment: .leading)
        .background(CardBackground(isSelected: false, cornerRadius: 14))
    }

    private var metricsSection: some View {
        let metricCardPresentations = VoiceInkDashboardPresentation.metricCards(
            isSnapshotLoaded: hasLoadedMetricsSnapshot,
            metrics: dashboardMetrics
        )

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
            ForEach(metricCardPresentations) { card in
                MetricCard(
                    icon: card.iconSystemName,
                    title: card.title,
                    value: card.value,
                    detail: card.detail,
                    color: metricAccent
                )
            }
        }
    }

    private var footerActionsView: some View {
        HStack(spacing: 12) {
            Button(action: {
                withAnimation(.smooth(duration: 0.3)) { isModelStatsPanelPresented = true }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: VoiceInkDashboardPresentation.modelPerformanceSystemImageName)
                    Text(VoiceInkDashboardPresentation.modelPerformanceButtonTitle)
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule(style: .continuous).fill(.thinMaterial))
            }
            .buttonStyle(.plain)
            .help(VoiceInkDashboardPresentation.modelPerformanceHelpText)
            CopySystemInfoButton()
        }
    }
    
    private var heroSubtitle: String {
        VoiceInkDashboardPresentation.heroSubtitle(
            isSnapshotLoaded: hasLoadedMetricsSnapshot,
            totalCount: totalCount,
            totalWords: totalWords
        )
    }

    private var metricAccent: Color {
        Color(nsColor: .controlAccentColor)
    }

    private var dashboardBackground: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
            LinearGradient(
                colors: [
                    Color(nsColor: .controlAccentColor).opacity(colorScheme == .dark ? 0.08 : 0.05),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    // MARK: - Computed Metrics

    private var dashboardMetrics: VoiceInkDashboardMetrics {
        VoiceInkDashboardMetrics(summary: VoiceInkDashboardMetricsSummary(
            totalCount: totalCount,
            totalWords: totalWords,
            totalDuration: totalDuration
        ))
    }

    private var timeSaved: TimeInterval {
        dashboardMetrics.timeSaved
    }
}

private struct CopySystemInfoButton: View {
    @State private var isCopied: Bool = false

    var body: some View {
        Button(action: {
            copySystemInfo()
        }) {
            HStack(spacing: 8) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .rotationEffect(.degrees(isCopied ? 360 : 0))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCopied)

                Text(isCopied ? "Copied!" : "Copy System Info")
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCopied)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule(style: .continuous).fill(.thinMaterial))
        }
        .buttonStyle(.plain)
        .scaleEffect(isCopied ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCopied)
    }

    private func copySystemInfo() {
        SystemInfoService.shared.copySystemInfoToClipboard()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isCopied = false
            }
        }
    }
}
