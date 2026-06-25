import SwiftUI
import os
import VoiceInkCore

#if canImport(Speech)
import Speech
#endif

struct NativeAppleLanguageAssetControl: View {
    private let logger = Logger(
        subsystem: VoiceInkAppIdentity.loggingSubsystem,
        category: VoiceInkMacOSLogCategory.nativeAppleLanguageAssetControl
    )

    let localeIdentifier: String
    let isVisible: Bool

    @State private var state: VoiceInkNativeAppleLanguageAssetState = .checking
    @State private var refreshTask: Task<Void, Never>?

    private var refreshKey: String {
        "\(isVisible)-\(localeIdentifier)"
    }

    var body: some View {
        Group {
            if isVisible {
                content
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .onChange(of: refreshKey, initial: true) { _, _ in
            refreshAssetState()
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    @ViewBuilder
    private var content: some View {
        let presentation = VoiceInkNativeAppleLanguageAssetPresentation.presentation(for: state)

        switch presentation.display {
        case .hidden:
            EmptyView()
        case .progress:
            ProgressView()
                .controlSize(.small)
                .frame(width: 28, height: 24)
                .help(presentation.helpText ?? "")
        case .actionButton(let systemImageName):
            Button(action: downloadAsset) {
                Image(systemName: systemImageName)
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .frame(width: 28, height: 24)
            .help(presentation.helpText ?? "")
            .accessibilityLabel(presentation.accessibilityLabel ?? "")
        case .statusIcon(let systemImageName):
            Image(systemName: systemImageName)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 28, height: 24)
                .help(presentation.helpText ?? "")
        }
    }

    private func refreshAssetState() {
        guard isVisible else {
            refreshTask?.cancel()
            refreshTask = nil
            return
        }

        let localeIdentifier = localeIdentifier
        state = .checking
        refreshTask?.cancel()
        refreshTask = Task {
            let resolvedState = await assetState(for: localeIdentifier)

            guard !Task.isCancelled else {
                return
            }

            state = resolvedState
        }
    }

    private func downloadAsset() {
        let localeIdentifier = localeIdentifier
        state = .downloading
        refreshTask?.cancel()

        refreshTask = Task {
            let resolvedState = await installAsset(for: localeIdentifier)

            guard !Task.isCancelled else {
                return
            }

            state = resolvedState
        }
    }

    private func assetState(for localeIdentifier: String) async -> VoiceInkNativeAppleLanguageAssetState {
        guard #available(macOS 26, *) else {
            return .assetManagementUnavailable
        }

        #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
        let locale = Locale(identifier: localeIdentifier)
        let selectedIdentifier = locale.identifier(.bcp47)
        let supportedIdentifiers = await Set(SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) })

        guard supportedIdentifiers.contains(selectedIdentifier) else {
            return .notSupported
        }

        let installedIdentifiers = await Set(SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) })
        return installedIdentifiers.contains(selectedIdentifier) ? .downloaded : .needsDownload
        #else
        return .assetManagementUnavailable
        #endif
    }

    private func installAsset(for localeIdentifier: String) async -> VoiceInkNativeAppleLanguageAssetState {
        guard #available(macOS 26, *) else {
            logger.error("\(VoiceInkNativeAppleLanguageAssetDiagnostics.downloadUnavailableRequiresMacOS26Message(localeIdentifier: localeIdentifier), privacy: .public)")
            return .assetManagementUnavailable
        }

        #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
        do {
            let locale = Locale(identifier: localeIdentifier)
            let normalizedIdentifier = locale.identifier(.bcp47)
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: []
            )

            let reservedLocales = await AssetInventory.reservedLocales
            for reservedLocale in reservedLocales {
                await AssetInventory.release(reservedLocale: reservedLocale)
            }

            let reserved = try await AssetInventory.reserve(locale: locale)

            if !reserved {
                let currentState = await assetState(for: localeIdentifier)
                if currentState != .needsDownload {
                    return currentState
                }

                logger.warning("\(VoiceInkNativeAppleLanguageAssetDiagnostics.reservationReturnedFalseMessage(normalizedIdentifier: normalizedIdentifier), privacy: .public)")
            }

            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
                return await assetState(for: localeIdentifier)
            }

            try await request.downloadAndInstall()
            return await assetState(for: localeIdentifier)
        } catch {
            logger.error("\(VoiceInkNativeAppleLanguageAssetDiagnostics.downloadFailedMessage(localeIdentifier: localeIdentifier, errorDescription: error.localizedDescription), privacy: .public)")
            return .failed(error.localizedDescription)
        }
        #else
        logger.error("\(VoiceInkNativeAppleLanguageAssetDiagnostics.downloadUnavailableFeatureFlagMessage(localeIdentifier: localeIdentifier), privacy: .public)")
        return .assetManagementUnavailable
        #endif
    }
}
