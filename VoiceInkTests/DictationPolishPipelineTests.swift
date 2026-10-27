import AVFoundation
import AppKit
import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
    @Suite(.serialized)
    struct DictationPolishPipelineTests {
        @Test @MainActor func lightFreezesRulesLanguageAndProfileBeforeRecognitionAndPastesLiterally() async throws {
            let fixture = try PolishRecordingFixture()
            do {
                VoiceInkDictationProfile.light.save()
                let rule = try fixture.replace("Roma", with: "RJT")
                let gate = fixture.gate()
                let work = fixture.run("Um, Roma", gate: gate)
                try await gate.waitUntilEntered()
                VoiceInkDictationProfile.custom.save()
                fixture.defaults.set("pt", forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
                rule.replacementText = "Later"
                try fixture.context.save()
                gate.release()
                let record = await work.value
                #expect(record.text == "RJT")
                #expect(record.recognitionText == "Um, Roma")
                #expect(record.dictationProfile == .light)
                #expect(record.clarityStyle == nil)
                #expect(record.enhancedText == nil)
                #expect(fixture.delivered == ["RJT"], "Custom lowercase, punctuation, cursor recasing and trailing-space preferences cannot change Light output.")
                #expect(fixture.enhancement.requests.isEmpty)
                #expect(fixture.enhancement.triggerCalls == 0)
                let saved = try fixture.saved(record.id)
                #expect(saved.text == "RJT" && saved.recognitionText == "Um, Roma" && saved.dictationProfile == .light)
                VoiceInkDictationProfile.light.save()
                let next = await fixture.run("Um, Roma").value
                #expect(next.text == "Um, Later")
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }

        @Test @MainActor func clarityKeepsCapturedProviderStyleRulesAndSameOutputSuccessMetadata() async throws {
            let fixture = try PolishRecordingFixture()
            do {
                VoiceInkDictationProfile.clarity.save()
                VoiceInkClarityStyle.formal.save()
                let rule = try fixture.replace("Roma", with: "RJT-482")
                fixture.enhancement.response = "RJT-482"
                let gate = fixture.gate()
                let work = fixture.run("Roma", gate: gate)
                try await gate.waitUntilEntered()
                VoiceInkDictationProfile.none.save()
                VoiceInkClarityStyle.casual.save()
                fixture.defaults.set(45, forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
                fixture.defaults.set("/bin/false", forKey: VoiceInkLocalCLIPreference.commandTemplateKey)
                rule.replacementText = "Later"
                try fixture.context.save()
                gate.release()
                let record = await work.value
                #expect(record.text == "RJT-482" && record.enhancedText == "RJT-482")
                #expect(record.recognitionText == "Roma")
                #expect(record.dictationProfile == .clarity && record.clarityStyle == .formal)
                #expect(record.processingFailureReason == nil)
                #expect(record.aiEnhancementModelName == "local-cli")
                #expect(record.enhancementDuration == 0.125)
                #expect(record.aiRequestSystemMessage == fixture.enhancement.requests.first?.systemMessage)
                #expect(record.aiRequestUserMessage == fixture.enhancement.requests.first?.userMessage)
                #expect(fixture.enhancement.requests.map(\.transcript) == ["RJT-482"])
                #expect(fixture.enhancement.requests.map(\.style) == [.formal])
                #expect(fixture.enhancement.snapshots.map(\.timeoutSeconds) == [10])
                #expect(fixture.enhancement.legacyCalls == 0 && fixture.enhancement.triggerCalls == 0)
                #expect(fixture.delivered == ["RJT-482"])
                #expect(fixture.states == [.enhancing])
                let saved = try fixture.saved(record.id)
                #expect(saved.enhancedText == "RJT-482" && saved.clarityStyle == .formal)
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }

        @Test @MainActor func wholeSnippetIsFrozenAndTerminalBeforeRulesOrMissingProvider() async throws {
            let fixture = try PolishRecordingFixture()
            do {
                let content = " \r\n<think>e\u{301}</think> {\"text\":\"literal\"} 🧪 "
                for profile in [VoiceInkDictationProfile.light, .clarity] {
                    profile.save()
                    try fixture.snippet("my signature", content: content)
                    let gate = fixture.gate()
                    let work = fixture.run("my signature", gate: gate, withEnhancement: false)
                    try await gate.waitUntilEntered()
                    try fixture.snippet("my signature", content: "Later")
                    gate.release()
                    let record = await work.value
                    #expect(record.text.utf8.elementsEqual(content.utf8))
                    #expect(record.text.utf16.elementsEqual(content.utf16))
                    #expect(record.recognitionText == "my signature")
                    #expect(record.dictationProfile == profile)
                    #expect(record.enhancedText == nil && record.processingFailureReason == nil)
                    #expect(record.aiRequestSystemMessage == nil && record.aiEnhancementModelName == nil)
                    #expect(fixture.delivered.last?.utf8.elementsEqual(content.utf8) == true)
                }
                #expect(fixture.enhancement.requests.isEmpty && fixture.states.isEmpty && fixture.warnings.isEmpty)
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }

        @Test @MainActor func clarityFailureReturnsUntouchedRecognitionAndWarnsAfterDeliveryOnce() async throws {
            let fixture = try PolishRecordingFixture()
            do {
                VoiceInkDictationProfile.clarity.save()
                try fixture.replace("Roma", with: "Prepared replacement")
                let raw = " \r\nRoma [keep] <think>stay</think> e\u{301} 🧪  "
                let failures: [Error] = [VoiceInkClarityError.invalidResponse, VoiceInkClarityError.emptyOutput, VoiceInkAIEnhancementError.timeout]
                for failure in failures {
                    fixture.enhancement.failure = failure
                    fixture.events = []
                    let count = fixture.warnings.count
                    let record = await fixture.run(raw).value
                    #expect(record.text.utf8.elementsEqual(raw.utf8))
                    #expect(record.text.utf16.elementsEqual(raw.utf16))
                    #expect(record.recognitionText == raw && record.dictationProfile == .clarity)
                    #expect(record.enhancedText == nil)
                    #expect(record.processingFailureReason == VoiceInkErrorDescription.text(for: failure))
                    #expect(record.aiRequestSystemMessage == nil && record.aiEnhancementModelName == nil && record.enhancementDuration == nil)
                    #expect(record.transcriptionState == .completed)
                    #expect(fixture.delivered.last?.utf8.elementsEqual(raw.utf8) == true)
                    #expect(fixture.warnings.count == count + 1)
                    #expect(fixture.warnings.last?.contains("The original was inserted.") == true)
                    #expect(fixture.events == ["delivered", "dismissed", "warning"])
                    let saved = try fixture.saved(record.id)
                    #expect(saved.processingFailureReason == record.processingFailureReason && saved.enhancedText == nil)
                }
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }

        @Test @MainActor func failedReplacementPreparationUsesRawExceptForTerminalLiteralSnippet() async throws {
            let fixture = try PolishRecordingFixture()
            do {
                let failure = DictationPostprocessingPlan.PreparationFailure.replacementLibrary("Owned unavailable library")
                let content = " \r\n{\"literal\":\"e\u{301}\"} 🧪 "
                let libraries = DictationPostprocessingPlan.Libraries(
                    snippets: [.init(trigger: "my signature", content: content)], replacementRules: .failure(failure))
                let plans: [DictationPostprocessingPlan] = [
                    .light(.init(libraries: libraries, storedLanguage: "en")),
                    .clarity(.init(libraries: libraries, style: .casual, provider: .failure(.providerConfiguration("Unavailable provider"))))
                ]
                for plan in plans {
                    let before = fixture.warnings.count
                    let raw = "  Um, Roma. 🧪 "
                    let fallback = await fixture.run(raw, plan: plan).value
                    #expect(fallback.text == raw && fallback.recognitionText == raw)
                    #expect(fallback.dictationProfile == plan.profile && fallback.enhancedText == nil)
                    #expect(fallback.processingFailureReason == VoiceInkErrorDescription.text(for: failure))
                    #expect(fixture.warnings.count == before + 1 && fixture.delivered.last == raw)
                    let snippet = await fixture.run("my signature", plan: plan).value
                    #expect(snippet.text.utf8.elementsEqual(content.utf8) && snippet.text.utf16.elementsEqual(content.utf16))
                    #expect(snippet.recognitionText == "my signature" && snippet.enhancedText == nil)
                    #expect(snippet.processingFailureReason == nil && fixture.warnings.count == before + 1)
                    #expect(snippet.clarityStyle == plan.clarityStyle)
                }
                #expect(fixture.enhancement.requests.isEmpty && fixture.states.isEmpty)
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }

        @Test @MainActor func missingProviderRecoversRawButBlankProfilesNeverPastePreviousText() async throws {
            let fixture = try PolishRecordingFixture()
            do {
                VoiceInkDictationProfile.clarity.save()
                let raw = "\n Roma unchanged 🧪 "
                let fallback = await fixture.run(raw, withEnhancement: false).value
                #expect(fallback.text == raw && fallback.recognitionText == raw)
                #expect(fallback.enhancedText == nil && fallback.processingFailureReason != nil)
                #expect(fixture.delivered == [raw] && fixture.warnings.count == 1)
                for profile in [VoiceInkDictationProfile.none, .light, .clarity] {
                    profile.save()
                    SpecialShortcutEmptyTranscriptionFallback.scheduleFallback()
                    let before = fixture.delivered.count
                    let record = await fixture.run(" \n\t ").value
                    #expect(record.text == " \n\t " && record.recognitionText == " \n\t ")
                    #expect(record.dictationProfile == profile && record.enhancedText == nil)
                    #expect(record.processingFailureReason == nil)
                    #expect(fixture.delivered.count == before)
                    let sentinel = Transcription(text: "", duration: 1, transcriptionStatus: .completed)
                    #expect(!SpecialShortcutEmptyTranscriptionFallback.consumeIfNeeded(
                        for: sentinel, modelContext: fixture.context,
                        writingActionUndoController: WritingActionUndoController()
                    ))
                }
                #expect(fixture.enhancement.requests.isEmpty && fixture.warnings.count == 1)
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }

        @Test @MainActor func cancellationBeforeProcessingRegistrationCannotLaunchClarity() async throws {
            let fixture = try PolishRecordingFixture()
            do {
                VoiceInkDictationProfile.clarity.save()
                let gate = fixture.gate()
                let work = fixture.run("Roma", gate: gate)
                try await gate.waitUntilEntered()
                fixture.cancelDelivery()
                gate.release()
                let record = await work.value
                try fixture.expectCanceled(record)
                #expect(fixture.enhancement.requests.isEmpty && fixture.states.isEmpty)
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }

        @Test @MainActor func undeliveredFallbackWarningDoesNotClaimInsertionOrDurableHistory() async throws {
            for readOnly in [false, true] {
                let fixture = try PolishRecordingFixture(readOnlyStore: readOnly)
                do {
                    VoiceInkDictationProfile.clarity.save()
                    fixture.enhancement.failure = VoiceInkClarityError.invalidResponse
                    fixture.preventDelivery()
                    let raw = "  Original e\u{301} 🧪 "
                    let record = await fixture.run(raw).value
                    #expect(record.text == raw && record.recognitionText == raw && record.enhancedText == nil)
                    #expect(record.processingFailureReason != nil)
                    #expect(fixture.delivered.isEmpty && fixture.warnings.count == 1)
                    #expect(fixture.events == ["not-delivered", "dismissed", "warning"])
                    #expect(fixture.warnings[0].contains("The original was retained."))
                    #expect(!fixture.warnings[0].contains("inserted") && !fixture.warnings[0].contains("History"))
                    if readOnly {
                        let fresh = ModelContext(fixture.container)
                        #expect(try fresh.fetch(FetchDescriptor<Transcription>()).isEmpty)
                        #expect(fixture.completions == 0)
                    } else {
                        #expect(try fixture.saved(record.id).text == raw)
                    }
                    await fixture.close()
                } catch { await fixture.close(); throw error }
            }
        }

        @Test @MainActor func blankResultCanceledWhileDismissalWaitsCannotCompleteOrRecordMetric() async throws {
            let fixture = try PolishRecordingFixture()
            do {
                VoiceInkDictationProfile.light.save()
                let dismissGate = fixture.gate()
                fixture.dismissGate = dismissGate
                let work = fixture.run(" \n\t ")
                try await dismissGate.waitUntilEntered()
                fixture.cancelDelivery()
                dismissGate.release()
                try fixture.expectCanceled(await work.value)
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }

        @Test @MainActor func operationCancellationCancelsOwnedProviderAndRejectsIgnoredLateSuccess() async throws {
            let fixture = try PolishRecordingFixture()
            do {
                VoiceInkDictationProfile.clarity.save()
                let providerGate = fixture.gate()
                fixture.enhancement.gate = providerGate
                let work = fixture.run("Roma")
                try await providerGate.waitUntilEntered()
                fixture.cancelDelivery()
                providerGate.release()
                let record = await work.value
                #expect(fixture.enhancement.sawCancellationAfterGate)
                #expect(fixture.enhancement.requests.count == 1)
                try fixture.expectCanceled(record)
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }

        @Test @MainActor func parentTaskCancellationCancelsOwnedProviderWithoutFallback() async throws {
            let fixture = try PolishRecordingFixture()
            do {
                VoiceInkDictationProfile.clarity.save()
                let providerGate = fixture.gate()
                fixture.enhancement.gate = providerGate
                let work = fixture.run("Roma")
                try await providerGate.waitUntilEntered()
                work.cancel()
                providerGate.release()
                let record = await work.value
                #expect(fixture.enhancement.sawCancellationAfterGate)
                try fixture.expectCanceled(record)
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }

        @Test @MainActor func customKeepsSnippetMappingAndNewRecognitionMetadata() async throws {
            let fixture = try PolishRecordingFixture()
            do {
                VoiceInkDictationProfile.custom.save()
                let content = "Exact <tag>snippet</tag>\n"
                try fixture.snippet("my signature", content: content)
                let record = await fixture.run("my signature").value
                #expect(record.text == "my signature" && record.enhancedText == content)
                #expect(record.recognitionText == "my signature" && record.dictationProfile == .custom)
                #expect(record.clarityStyle == nil && record.processingFailureReason == nil)
                #expect(fixture.delivered == [content] && fixture.enhancement.requests.isEmpty)
                let ordinary = await fixture.run("Ordinary Words.").value
                #expect(ordinary.text == "ordinary words" && ordinary.enhancedText == nil)
                #expect(ordinary.recognitionText == "Ordinary Words." && ordinary.dictationProfile == .custom)
                #expect(fixture.delivered.last == "ordinary words ")
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }

        @Test @MainActor func acceptedEngineStartCapturesPlanBeforePermissionAndKeepsItAfterResourceCleanup() async throws {
            let fixture = try PolishRecordingFixture()
            do {
                VoiceInkDictationProfile.clarity.save()
                VoiceInkClarityStyle.formal.save()
                let engine = fixture.engine()
                let permission = fixture.gate()
                engine.recordPermissionRequestForTesting = { await permission.enter(); return true }
                let start = fixture.engineTask { await engine.toggleRecord() }
                try await permission.waitUntilEntered()
                #expect(engine.activeDictationPlan.profile == .clarity && engine.activeDictationPlan.clarityStyle == .formal)
                VoiceInkDictationProfile.none.save()
                VoiceInkClarityStyle.casual.save()
                fixture.defaults.set(45, forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
                permission.release()
                await start.value
                #expect(engine.recordingState == .recording)
                await engine.cleanupResources()
                #expect(engine.activeDictationPlan.profile == .clarity && engine.activeDictationPlan.clarityStyle == .formal)
                await fixture.engineTask { await engine.toggleRecord() }.value
                let record = try #require(fixture.records().first)
                #expect(record.dictationProfile == .clarity && record.clarityStyle == .formal)
                #expect(fixture.enhancement.snapshots.map(\.timeoutSeconds) == [10])
                #expect(engine.recordingState == .idle)
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }

        @Test @MainActor func heldOldRecorderStopCannotRetargetOrClearANewerAcceptedRun() async throws {
            let fixture = try PolishRecordingFixture()
            do {
                VoiceInkDictationProfile.light.save()
                let engine = fixture.engine()
                await fixture.engineTask { await engine.toggleRecord() }.value
                let oldURL = try #require(engine.recordedFile)
                let oldSession = try #require(fixture.registry.sessions.first)
                let stopGate = fixture.gate()
                fixture.recorder.nextStopGate = stopGate
                let oldStop = fixture.engineTask { await engine.toggleRecord() }
                try await stopGate.waitUntilEntered()
                VoiceInkDictationProfile.none.save()
                let newerModel = fixture.model("newer")
                engine.transcriptionModelManager.currentTranscriptionModel = newerModel
                fixture.registry.recognizedText = "  New recording. 🧪 "
                await fixture.engineTask { await engine.toggleRecord() }.value
                let newURL = try #require(engine.recordedFile)
                let newSession = try #require(engine.currentSession)
                #expect(newURL != oldURL && engine.recordingState == .recording)
                stopGate.release()
                await oldStop.value
                #expect(engine.recordedFile == newURL && engine.recordingState == .recording)
                #expect(engine.currentSession === newSession)
                #expect(engine.activeDictationPlan.profile == .none)
                #expect(oldSession.cancelCalls > 0)
                #expect(fixture.delivered.isEmpty)
                let canceled = try #require(fixture.records().first { $0.audioFileURL == oldURL.absoluteString })
                #expect(canceled.transcriptionState == .canceled && canceled.duration > 0)
                #expect(canceled.recognitionText == nil && canceled.enhancedText == nil)
                #expect(canceled.transcriptionModelName == "Owned recording original")
                await fixture.engineTask { await engine.toggleRecord() }.value
                let completed = try #require(fixture.records().first { $0.audioFileURL == newURL.absoluteString })
                #expect(completed.transcriptionState == .completed && completed.dictationProfile == VoiceInkDictationProfile.none)
                #expect(completed.transcriptionModelName == newerModel.displayName)
                #expect(completed.recognitionText == "  New recording. 🧪 ")
                #expect(fixture.delivered == ["  New recording. 🧪 "])
                #expect(engine.recordingState == .idle && engine.recordedFile == nil)
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }

        @Test @MainActor func newAcceptedRunCancelsOlderProviderAndRejectsItsLateCompletion() async throws {
            let fixture = try PolishRecordingFixture()
            do {
                VoiceInkDictationProfile.clarity.save()
                let engine = fixture.engine()
                await fixture.engineTask { await engine.toggleRecord() }.value
                let oldURL = try #require(engine.recordedFile)
                let providerGate = fixture.gate()
                fixture.enhancement.gate = providerGate
                let oldStop = fixture.engineTask { await engine.toggleRecord() }
                try await providerGate.waitUntilEntered()
                VoiceInkDictationProfile.none.save()
                fixture.registry.recognizedText = "New raw recording."
                await fixture.engineTask { await engine.toggleRecord() }.value
                let newURL = try #require(engine.recordedFile)
                let newSession = try #require(engine.currentSession)
                providerGate.release()
                await oldStop.value
                #expect(fixture.enhancement.sawCancellationAfterGate)
                #expect(engine.recordedFile == newURL && engine.recordingState == .recording)
                #expect(engine.currentSession === newSession && engine.activeDictationPlan.profile == .none)
                let old = try #require(fixture.records().first { $0.audioFileURL == oldURL.absoluteString })
                #expect(old.transcriptionState == .canceled && old.enhancedText == nil)
                #expect(old.recognitionText == nil && old.processingFailureReason == nil)
                #expect(fixture.delivered.isEmpty)
                await fixture.engineTask { await engine.toggleRecord() }.value
                #expect(fixture.delivered == ["New raw recording."])
                #expect(engine.recordingState == .idle && engine.recordedFile == nil)
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }

        @Test @MainActor func heldCancellationCannotClearContextCapturedByANewerAcceptedRun() async throws {
            let fixture = try PolishRecordingFixture()
            do {
                VoiceInkDictationProfile.light.save()
                let engine = fixture.engine()
                await fixture.engineTask { await engine.toggleRecord() }.value
                let oldURL = try #require(engine.recordedFile)
                let stopGate = fixture.gate()
                fixture.recorder.nextStopGate = stopGate
                let oldCancellation = fixture.engineTask { await engine.cancelRecording() }
                try await stopGate.waitUntilEntered()
                // Public reset reaches idle while the earlier cancellation still owns its held stop.
                await fixture.engineTask { await engine.resetRecordingSession() }.value
                VoiceInkDictationProfile.custom.save()
                await fixture.engineTask { await engine.toggleRecord() }.value
                await engine.recordingStartupTask?.value
                let newURL = try #require(engine.recordedFile)
                let newSession = try #require(engine.currentSession)
                let context = try #require(fixture.enhancement.capturedContextMarker)
                let clears = fixture.enhancement.clearContextCalls
                stopGate.release()
                await oldCancellation.value
                #expect(engine.recordedFile == newURL && newURL != oldURL)
                #expect(engine.currentSession === newSession && engine.recordingState == .recording)
                #expect(engine.activeDictationPlan.profile == .custom)
                #expect(fixture.enhancement.capturedContextMarker == context)
                #expect(fixture.enhancement.clearContextCalls == clears)
                let canceled = try #require(fixture.records().first { $0.audioFileURL == oldURL.absoluteString })
                #expect(canceled.transcriptionState == .canceled && canceled.recognitionText == nil)
                await fixture.engineTask { await engine.toggleRecord() }.value
                #expect(fixture.delivered.count == 1 && engine.recordingState == .idle)
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }

        @Test @MainActor func resetCleanupCannotClearContextCapturedByANewerAcceptedRun() async throws {
            let fixture = try PolishRecordingFixture()
            do {
                VoiceInkDictationProfile.light.save()
                let engine = fixture.engine()
                await fixture.engineTask { await engine.toggleRecord() }.value
                let stopGate = fixture.gate()
                let cleanupGate = fixture.gate()
                fixture.recorder.nextStopGate = stopGate
                fixture.registry.nextCleanupGate = cleanupGate
                let oldReset = fixture.engineTask { await engine.resetRecordingSession() }
                try await stopGate.waitUntilEntered()
                stopGate.release()
                try await cleanupGate.waitUntilEntered()
                #expect(engine.recordingState == .idle)
                VoiceInkDictationProfile.custom.save()
                await fixture.engineTask { await engine.toggleRecord() }.value
                await engine.recordingStartupTask?.value
                let newURL = try #require(engine.recordedFile)
                let newSession = try #require(engine.currentSession)
                let context = try #require(fixture.enhancement.capturedContextMarker)
                let clears = fixture.enhancement.clearContextCalls
                cleanupGate.release()
                await oldReset.value
                #expect(engine.recordedFile == newURL && engine.currentSession === newSession)
                #expect(engine.recordingState == .recording && engine.activeDictationPlan.profile == .custom)
                #expect(fixture.enhancement.capturedContextMarker == context)
                #expect(fixture.enhancement.clearContextCalls == clears)
                await fixture.engineTask { await engine.toggleRecord() }.value
                #expect(fixture.delivered.count == 1 && engine.recordingState == .idle)
                await fixture.close()
            } catch { await fixture.close(); throw error }
        }
    }
}

private enum PolishRecordingFailure: Error { case unusedRuntime, timeout }

@MainActor
private final class PolishRecordingFixture {
    let defaults = UserDefaults.standard
    let container: ModelContainer
    let context: ModelContext
    let directory: URL
    let enhancement: PolishRecordingEnhancement
    let registry: PolishRecordingRegistry
    let recorder = PolishRecordingRecorder()
    private let provider = PolishRecordingUnusedWhisper()
    private let savedDefaults: [String: Any]
    private let savedPowerMode: PowerModeConfig?
    private let savedConfigurations: [PowerModeConfig]
    private let savedSound: Bool
    private var gates: [PolishRecordingGate] = []
    private var tasks: [Task<Transcription, Never>] = []
    private var engineTasks: [Task<Void, Never>] = []
    private var pipelines: [TranscriptionPipeline] = []
    private var engines: [VoiceInkEngine] = []
    private var contexts: [ModelContext] = []
    private var currentRecordID: UUID?
    private var observer: NSObjectProtocol?
    private var ownedIDs = Set<UUID>()
    private var clipboardSnapshot: [[(NSPasteboard.PasteboardType, Data)]]?
    private var ownedClipboardChangeCount: Int?
    var dismissGate: PolishRecordingGate?
    var delivered: [String] = []
    var warnings: [String] = []
    var events: [String] = []
    var states: [VoiceInkRecordingState] = []
    var cancelCalls = 0
    var completions = 0
    private static let keys = [
        VoiceInkDictationProfile.storageKey, VoiceInkClarityStyle.storageKey, VoiceInkSpokenSnippets.userDefaultsKey,
        VoiceInkUserDefaultsKey.selectedTranscriptionLanguage, VoiceInkUserDefaultsKey.selectedAIProvider,
        VoiceInkUserDefaultsKey.isAIEnhancementEnabled, VoiceInkUserDefaultsKey.customPrompts,
        VoiceInkUserDefaultsKey.selectedPromptId, VoiceInkUserDefaultsKey.useClipboardContext,
        VoiceInkUserDefaultsKey.useScreenCaptureContext, VoiceInkUserDefaultsKey.enhancementTimeoutSeconds,
        VoiceInkUserDefaultsKey.enhancementRetryOnTimeout, VoiceInkLocalCLIPreference.commandTemplateKey,
        VoiceInkLocalCLIPreference.timeoutSecondsKey, VoiceInkLocalCLIPreference.selectedTemplateKey,
        VoiceInkUserDefaultsKey.isTextFormattingEnabled, VoiceInkUserDefaultsKey.lowercaseTranscription,
        VoiceInkUserDefaultsKey.removeFillerWords, VoiceInkUserDefaultsKey.fillerWords,
        VoiceInkUserDefaultsKey.appendTrailingSpace, VoiceInkUserDefaultsKey.skipShortEnhancement,
        VoiceInkUserDefaultsKey.prewarmModelOnWake, VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled,
        VoiceInkUserDefaultsKey.isAudioCleanupEnabled, PunctuationCleanupMode.userDefaultsKey,
        PunctuationCleanupMode.legacyRemovePunctuationKey,
        VoiceInkPasteMethod.userDefaultsKey, VoiceInkRecordingFeedbackPreference.isSoundFeedbackEnabledKey,
        VoiceInkUserDefaultsKey.activePowerModeConfigurationId, VoiceInkUserDefaultsKey.powerModePersistConfig
    ]

    init(readOnlyStore: Bool = false) throws {
        let domain = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) } ?? [:]
        savedDefaults = Dictionary(uniqueKeysWithValues: Self.keys.compactMap { key in domain[key].map { (key, $0) } })
        savedPowerMode = PowerModeManager.shared.activeConfiguration
        savedConfigurations = PowerModeManager.shared.configurations
        savedSound = SoundManager.shared.isEnabled
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("RJT-Polish-Recording-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let schema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self])
        if readOnlyStore {
            let url = directory.appendingPathComponent("read-only.store")
            try Self.seedStore(schema: schema, at: url)
            let configuration = ModelConfiguration("PolishRecordingReadOnly", schema: schema, url: url,
                allowsSave: false, cloudKitDatabase: .none)
            try #require(!configuration.allowsSave && configuration.groupAppContainerIdentifier == nil && configuration.cloudKitContainerIdentifier == nil)
            container = try ModelContainer(for: schema, configurations: [configuration])
        } else {
            let configuration = ModelConfiguration("PolishRecording-\(UUID().uuidString)", schema: schema,
                isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none)
            container = try ModelContainer(for: schema, configurations: [configuration])
        }
        context = ModelContext(container)
        context.autosaveEnabled = false
        registry = PolishRecordingRegistry(modelProvider: provider, modelsDirectory: directory, modelContext: context,
            qwenRuntimeResult: .failure(PolishRecordingFailure.unusedRuntime))
        defaults.set(VoiceInkAIEnhancementProviderKind.localCLI.rawValue, forKey: VoiceInkUserDefaultsKey.selectedAIProvider)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.isAIEnhancementEnabled)
        defaults.set(Data("[]".utf8), forKey: VoiceInkUserDefaultsKey.customPrompts)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedPromptId)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.useClipboardContext)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.useScreenCaptureContext)
        defaults.set(10, forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.enhancementRetryOnTimeout)
        defaults.set("/bin/cat", forKey: VoiceInkLocalCLIPreference.commandTemplateKey)
        defaults.set(5, forKey: VoiceInkLocalCLIPreference.timeoutSecondsKey)
        defaults.set("en", forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
        defaults.set(true, forKey: VoiceInkUserDefaultsKey.isTextFormattingEnabled)
        defaults.set(true, forKey: VoiceInkUserDefaultsKey.lowercaseTranscription)
        defaults.set(true, forKey: VoiceInkUserDefaultsKey.removeFillerWords)
        defaults.set(["um"], forKey: VoiceInkUserDefaultsKey.fillerWords)
        defaults.set(true, forKey: VoiceInkUserDefaultsKey.appendTrailingSpace)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.skipShortEnhancement)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.prewarmModelOnWake)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled)
        defaults.set(false, forKey: VoiceInkUserDefaultsKey.isAudioCleanupEnabled)
        defaults.set(true, forKey: VoiceInkUserDefaultsKey.powerModePersistConfig)
        defaults.removeObject(forKey: VoiceInkSpokenSnippets.userDefaultsKey)
        PunctuationCleanupMode.setCurrent(.removeAll)
        VoiceInkPasteMethod.setCurrent(.standard)
        PowerModeManager.shared.configurations = []
        PowerModeManager.shared.activeConfiguration = nil
        SoundManager.shared.isEnabled = false
        SpecialShortcutEmptyTranscriptionFallback.clear()
        let ai = AIService()
        try #require(ai.selectedProvider == .localCLI && ai.isAPIKeyValid && ai.apiKey.isEmpty)
        enhancement = PolishRecordingEnhancement(aiService: ai, modelContext: context)
        CursorPaster.configureAccessibilityTextInserterForTesting { [weak self] text, _ in
            self?.delivered.append(text)
            self?.events.append("delivered")
            return .inserted
        }
        observer = NotificationCenter.default.addObserver(forName: .transcriptionCompleted, object: nil, queue: .main) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let record = event.object as? Transcription, self.ownedIDs.contains(record.id) else { return }
                self.completions += 1
            }
        }
    }

    private static func seedStore(schema: Schema, at url: URL) throws {
        let configuration = ModelConfiguration("PolishRecordingReadOnly", schema: schema, url: url, cloudKitDatabase: .none)
        let seed = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(seed)
        context.autosaveEnabled = false
        context.insert(VocabularyWord(word: "Owned read-only seed"))
        try context.save()
    }

    func preventDelivery() {
        let pasteboard = NSPasteboard.general
        clipboardSnapshot = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        CursorPaster.configureAccessibilityTextInserterForTesting { _, _ in .unsupported }
        CursorPaster.configurePasteCommandPosterForTesting { [weak self] _ in
            self?.ownedClipboardChangeCount = pasteboard.changeCount
            self?.events.append("not-delivered")
            return .commandNotPosted
        }
    }

    @discardableResult func replace(_ text: String, with replacement: String) throws -> WordReplacement {
        let value = WordReplacement(originalText: text, replacementText: replacement)
        context.insert(value)
        try context.save()
        return value
    }

    func snippet(_ text: String, content: String) throws {
        try VoiceInkSpokenSnippets.save([.init(trigger: text, content: content)])
    }

    func gate() -> PolishRecordingGate {
        let value = PolishRecordingGate()
        gates.append(value)
        return value
    }

    func model(_ name: String = "original") -> CloudModel {
        CloudModel(spec: .init(name: "owned-recording-\(name)", displayName: "Owned recording \(name)", description: "Owned fixture",
            speed: 1, accuracy: 1, isMultilingual: true), provider: .groq)
    }

    func run(_ raw: String, gate: PolishRecordingGate? = nil, withEnhancement: Bool = true,
             plan: DictationPostprocessingPlan? = nil) -> Task<Transcription, Never> {
        let record = Transcription(text: "", duration: 1)
        ownedIDs.insert(record.id)
        currentRecordID = record.id
        context.insert(record)
        let pipeline = TranscriptionPipeline(modelContext: context, serviceRegistry: registry,
            enhancementService: withEnhancement ? enhancement : nil,
            reportProcessingFailure: { [weak self] reason in self?.warnings.append(reason); self?.events.append("warning") })
        pipelines.append(pipeline)
        let session = PolishRecordingSession(text: raw, gate: gate)
        let work = Task {
            await pipeline.run(transcription: record, audioURL: directory.appendingPathComponent("unused.wav"), model: model(), session: session,
                dictationPlan: plan,
                latencyTraceToken: nil, onStateChange: { self.states.append($0) }, shouldCancel: { false },
                onCancel: { self.cancelCalls += 1 }, onDismiss: {
                    self.events.append("dismissed")
                    await self.dismissGate?.enter()
                })
            return record
        }
        tasks.append(work)
        return work
    }

    func cancelDelivery() {
        guard let currentRecordID else { Issue.record("No owned recording was registered."); return }
        for pipeline in pipelines { pipeline.cancelDelivery(for: currentRecordID) }
    }

    func expectCanceled(_ record: Transcription) throws {
        #expect(record.transcriptionState == .canceled)
        #expect(record.enhancedText == nil && record.processingFailureReason == nil)
        #expect(record.recognitionText == nil && record.dictationProfile == nil && record.clarityStyle == nil)
        #expect(record.aiEnhancementModelName == nil && record.aiRequestSystemMessage == nil)
        #expect(delivered.isEmpty && warnings.isEmpty && completions == 0 && cancelCalls == 1)
        #expect(try context.fetch(FetchDescriptor<SessionMetric>()).isEmpty)
        #expect(try saved(record.id).transcriptionState == .canceled)
    }

    func engine() -> VoiceInkEngine {
        let whisper = WhisperModelManager(modelsDirectory: directory)
        let models = TranscriptionModelManager(whisperModelManager: whisper, fluidAudioModelManager: FluidAudioModelManager())
        models.currentTranscriptionModel = model()
        let value = VoiceInkEngine(modelContext: context, whisperModelManager: whisper, transcriptionModelManager: models,
            qwenRuntimeResult: .failure(PolishRecordingFailure.unusedRuntime), enhancementService: enhancement,
            recorder: recorder, serviceRegistry: registry)
        value.recordPermissionRequestForTesting = { true }
        engines.append(value)
        return value
    }

    func engineTask(_ body: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let work = Task { await body() }
        engineTasks.append(work)
        return work
    }

    func records() throws -> [Transcription] { try context.fetch(FetchDescriptor<Transcription>()) }
    func saved(_ id: UUID) throws -> Transcription {
        let fresh = ModelContext(container)
        contexts.append(fresh)
        return try #require(fresh.fetch(FetchDescriptor<Transcription>()).first { $0.id == id })
    }

    func close() async {
        for task in tasks { task.cancel() }
        for task in engineTasks { task.cancel() }
        for gate in gates { gate.release() }
        for task in tasks { _ = await task.value }
        for task in engineTasks { await task.value }
        for engine in engines { await engine.resetRecordingSession() }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        CursorPaster.configureAccessibilityTextInserterForTesting()
        CursorPaster.configurePasteCommandPosterForTesting()
        if let clipboardSnapshot, NSPasteboard.general.changeCount == ownedClipboardChangeCount {
            NSPasteboard.general.clearContents()
            let items = clipboardSnapshot.map { snapshot in
                let item = NSPasteboardItem()
                for (type, data) in snapshot { item.setData(data, forType: type) }
                return item
            }
            if !items.isEmpty { NSPasteboard.general.writeObjects(items) }
        }
        SpecialShortcutEmptyTranscriptionFallback.clear()
        for url in recorder.files where url.deletingLastPathComponent() == VoiceInkMacOSStorageDirectories.recordingsDirectory {
            if FileManager.default.fileExists(atPath: url.path) {
                do { try FileManager.default.removeItem(at: url) }
                catch { Issue.record("Could not remove owned recorder fixture: \(error)") }
            }
        }
        PowerModeManager.shared.configurations = savedConfigurations
        PowerModeManager.shared.activeConfiguration = savedPowerMode
        SoundManager.shared.isEnabled = savedSound
        for key in Self.keys {
            if let value = savedDefaults[key] { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record("Could not remove owned recording fixture: \(error)") }
    }
}

@MainActor
private final class PolishRecordingEnhancement: AIEnhancementService {
    var response = "Polished output"
    var failure: Error?
    var gate: PolishRecordingGate?
    var requests: [VoiceInkClarityRequest] = []
    var snapshots: [AIEnhancementProviderSnapshot] = []
    var sawCancellationAfterGate = false
    var legacyCalls = 0
    var triggerCalls = 0
    var capturedContextMarker: UUID?
    var clearContextCalls = 0
    override func captureClipboardContext() { capturedContextMarker = UUID() }
    override func captureScreenContext() async {}
    override func clearCapturedContexts() { clearContextCalls += 1; capturedContextMarker = nil }
    override func performClarity(request: VoiceInkClarityRequest, using snapshot: AIEnhancementProviderSnapshot) async throws -> VoiceInkAIEnhancementResult {
        requests.append(request)
        snapshots.append(snapshot)
        await gate?.enter()
        sawCancellationAfterGate = Task.isCancelled
        // Deliberately ignore cancellation: the real pipeline must reject a late backend result.
        if let failure { throw failure }
        return VoiceInkAIEnhancementResult(text: response, duration: 0.125, modelName: snapshot.modelName,
            promptName: nil, requestSystemMessage: request.systemMessage, requestUserMessage: request.userMessage)
    }
    override func enhance(_ text: String) async throws -> VoiceInkAIEnhancementResult {
        legacyCalls += 1
        throw PolishRecordingFailure.unusedRuntime
    }
    override func analyzePromptTrigger(in text: String) -> VoiceInkPromptDetectionResult {
        triggerCalls += 1
        return super.analyzePromptTrigger(in: text)
    }
}

@MainActor
private final class PolishRecordingRegistry: TranscriptionServiceRegistry {
    var recognizedText = "Um, Roma"
    var sessions: [PolishRecordingSession] = []
    var nextCleanupGate: PolishRecordingGate?
    override func createSession(for model: any TranscriptionModel, onPartialTranscript: ((String) -> Void)? = nil) -> TranscriptionSession {
        let session = PolishRecordingSession(text: recognizedText, gate: nil)
        sessions.append(session)
        return session
    }
    override func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String { recognizedText }
    override func cleanup() async {
        let gate = nextCleanupGate
        nextCleanupGate = nil
        await gate?.enter()
    }
}

@MainActor
private final class PolishRecordingUnusedWhisper: WhisperModelProvider {
    let isModelLoaded = false
    let whisperContext: WhisperContext? = nil
    let loadedWhisperModel: VoiceInkWhisperLocalModelFile? = nil
    let availableModels: [VoiceInkWhisperLocalModelFile] = []
}

@MainActor
private final class PolishRecordingSession: TranscriptionSession {
    let text: String
    let gate: PolishRecordingGate?
    var cancelCalls = 0
    init(text: String, gate: PolishRecordingGate?) { self.text = text; self.gate = gate }
    func prepare(model: any TranscriptionModel, latencyTraceToken: VoiceInkLatencyTrace.Token?) async throws -> ((Data) -> Void)? { nil }
    func transcribe(audioURL: URL) async throws -> String { await gate?.enter(); return text }
    func cancel() { cancelCalls += 1 }
}

@MainActor
private final class PolishRecordingRecorder: Recorder {
    var nextStopGate: PolishRecordingGate?
    var files: [URL] = []
    override func startRecording(toOutputFile url: URL, latencyTraceToken: VoiceInkLatencyTrace.Token?) async throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600))
        buffer.frameLength = 1_600
        let channels = try #require(buffer.floatChannelData)
        channels[0].initialize(repeating: 0, count: 1_600)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        files.append(url)
    }
    override func stopRecording(latencyTraceToken: VoiceInkLatencyTrace.Token? = nil) async {
        let gate = nextStopGate
        nextStopGate = nil
        await gate?.enter()
    }
}

@MainActor
private final class PolishRecordingGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var entered = false
    private var released = false
    func enter() async {
        entered = true
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilEntered() async throws {
        for _ in 0..<300 {
            if entered { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw PolishRecordingFailure.timeout
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}
