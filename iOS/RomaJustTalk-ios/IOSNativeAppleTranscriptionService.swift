import AVFoundation
import Foundation
import OSLog
import RomaCore

#if canImport(Speech)
import Speech
#endif

struct IOSNativeAppleTranscriptionService: RomaAudioTranscriptionService {
    func transcribeAudioFile(
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String? = nil,
        prompt: String? = nil,
        customVocabulary: [String] = []
    ) async throws -> String {
        guard model == RomaTranscriptionModelCatalog.nativeAppleModel.name else {
            throw RomaNativeAppleTranscriptionFailureKind.invalidModel
        }

        guard #available(iOS 26.0, *) else {
            RomaIOSLogger.nativeAppleTranscription.error(
                "\(RomaNativeAppleTranscriptionPolicy.unsupportedIOSDiagnosticMessage, privacy: .public)"
            )
            throw RomaNativeAppleTranscriptionFailureKind.unsupportedIOS
        }

        #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
        return try await IOSNativeAppleSpeechRuntime.transcribe(
            fileURL: fileURL,
            localeIdentifier: language ?? "en-US"
        )
        #else
        throw RomaNativeAppleTranscriptionFailureKind.unsupportedIOS
        #endif
    }
}

enum IOSNativeAppleSpeechRuntime {
    static func assetState(
        for localeIdentifier: String
    ) async -> RomaNativeAppleLanguageAssetState {
        guard #available(iOS 26.0, *) else {
            return .assetManagementUnavailable
        }

        #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
        let normalizedIdentifier = Locale(identifier: localeIdentifier).identifier(.bcp47)
        let supported = await Set(SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) })
        guard supported.contains(normalizedIdentifier) else {
            return .notSupported
        }

        let installed = await Set(SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) })
        return installed.contains(normalizedIdentifier) ? .downloaded : .needsDownload
        #else
        return .assetManagementUnavailable
        #endif
    }

    static func installAsset(
        for localeIdentifier: String
    ) async -> RomaNativeAppleLanguageAssetState {
        guard #available(iOS 26.0, *) else {
            return .assetManagementUnavailable
        }

        #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
        do {
            let locale = Locale(identifier: localeIdentifier)
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: []
            )
            try await reserve(locale: locale, modules: [transcriber])

            guard let request = try await AssetInventory.assetInstallationRequest(
                supporting: [transcriber]
            ) else {
                return await assetState(for: localeIdentifier)
            }

            try await request.downloadAndInstall()
            return await assetState(for: localeIdentifier)
        } catch {
            RomaIOSLogger.nativeAppleLanguageAssets.error(
                "\(RomaNativeAppleLanguageAssetDiagnostics.downloadFailedMessage(localeIdentifier: localeIdentifier, errorDescription: error.localizedDescription), privacy: .public)"
            )
            return .failed(error.localizedDescription)
        }
        #else
        return .assetManagementUnavailable
        #endif
    }

    @available(iOS 26.0, *)
    static func transcribe(
        fileURL: URL,
        localeIdentifier: String
    ) async throws -> String {
        #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
        let audioFile = try AVAudioFile(forReading: fileURL)
        let audioDuration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
        let locale = Locale(identifier: localeIdentifier)
        let normalizedIdentifier = locale.identifier(.bcp47)
        let displayName = RomaLanguageCatalog.nativeAppleDisplayName(for: normalizedIdentifier)

        switch await assetState(for: normalizedIdentifier) {
        case .notSupported:
            throw RomaNativeAppleTranscriptionFailureKind.localeNotSupported
        case .needsDownload:
            throw RomaNativeAppleTranscriptionFailureKind.assetDownloadRequired(
                displayName: displayName
            )
        case .downloaded:
            break
        case .checking, .downloading, .failed, .assetManagementUnavailable:
            throw RomaNativeAppleTranscriptionFailureKind.transcriptionFailed
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        try await reserve(locale: locale, modules: [transcriber])

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let resultTask = Task<String, Error> {
            var transcript = ""
            for try await result in transcriber.results {
                transcript += String(result.text.characters)
            }
            return transcript
        }

        do {
            guard let lastSampleTime = try await analyzer.analyzeSequence(from: audioFile) else {
                resultTask.cancel()
                await analyzer.cancelAndFinishNow()
                throw RomaNativeAppleTranscriptionFailureKind.transcriptionFailed
            }
            try await analyzer.finalizeAndFinish(through: lastSampleTime)
        } catch {
            resultTask.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }

        do {
            return try await waitForResultStream(
                resultTask,
                timeout: RomaNativeAppleTranscriptionPolicy.resultStreamTimeout(
                    forAudioDuration: audioDuration
                )
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            resultTask.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
        #else
        throw RomaNativeAppleTranscriptionFailureKind.unsupportedIOS
        #endif
    }

    #if canImport(Speech) && ENABLE_NATIVE_SPEECH_ANALYZER
    @available(iOS 26.0, *)
    private static func reserve(
        locale: Locale,
        modules: [any SpeechModule]
    ) async throws {
        let normalizedIdentifier = locale.identifier(.bcp47)
        let reservedLocales = await AssetInventory.reservedLocales
        guard !reservedLocales.contains(where: {
            $0.identifier(.bcp47) == normalizedIdentifier
        }) else {
            return
        }

        for reservedLocale in reservedLocales {
            await AssetInventory.release(reservedLocale: reservedLocale)
        }

        _ = try await AssetInventory.reserve(locale: locale)
        _ = await AssetInventory.status(forModules: modules)
    }
    #endif

    private static func waitForResultStream(
        _ resultTask: Task<String, Error>,
        timeout: TimeInterval
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await resultTask.value
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw RomaNativeAppleTranscriptionFailureKind.resultStreamTimedOut
            }

            guard let result = try await group.next() else {
                throw RomaNativeAppleTranscriptionFailureKind.transcriptionFailed
            }
            group.cancelAll()
            return result
        }
    }
}
