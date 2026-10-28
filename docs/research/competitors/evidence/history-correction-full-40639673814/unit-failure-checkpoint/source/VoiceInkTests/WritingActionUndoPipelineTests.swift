import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
    @Suite(.serialized)
    struct WritingActionUndoPipelineTests {
        @Test @MainActor func confirmedRewriteCommitsUndoBeforeLateCancellationAndKeepsItAfterCompletion() async throws {
            let fixture = try WritingDeliveryFixture()
            defer { fixture.close() }
            let controller = WritingActionUndoController()
            let pipeline = Self.pipeline(fixture, controller: controller)
            fixture.access.afterMutation = { fixture.canceled = true }
            let record = try await fixture.run(pipeline: pipeline)
            #expect(record.transcriptionState == .completed)
            #expect(fixture.access.attempts == 1)
            #expect(controller.isAvailable && !controller.isBusy)
            #expect(fixture.cancellations == 0)
            fixture.access.afterMutation = nil
            fixture.canceled = false
            #expect(await controller.undo().didRestoreText)
            #expect(fixture.access.value == "prefix old suffix")
            #expect(fixture.access.range == NSRange(location: 7, length: 3))
            #expect(fixture.access.attempts == 2)
            #expect(!controller.isAvailable)
        }

        @Test @MainActor func translateAndDraftConfirmDeliveryWithoutCreatingRewriteUndo() async throws {
            for kind in [VoiceInkWritingActionKind.translate, .draft] {
                let fixture = try WritingDeliveryFixture()
                defer { fixture.close() }
                let controller = WritingActionUndoController()
                let pipeline = Self.pipeline(fixture, controller: controller)
                fixture.access.afterMutation = { fixture.canceled = true }
                let record = try await fixture.run(kind: kind, pipeline: pipeline)
                #expect(record.transcriptionState == .completed)
                #expect(record.enhancedText == fixture.enhancement.output)
                #expect(fixture.access.attempts == 1)
                #expect(!controller.isAvailable && !controller.isBusy)
                #expect(fixture.cancellations == 0)
                guard case .unavailable = await controller.undo() else { Issue.record("Non-rewrite armed Undo."); continue }
                #expect(fixture.access.attempts == 1)
            }
        }

        @Test @MainActor func generationFailureBeforeAnyAttemptLeavesThePreviousConfirmedEditUndoable() async throws {
            let fixture = try WritingDeliveryFixture()
            defer { fixture.close() }
            let controller = WritingActionUndoController()
            let pipeline = Self.pipeline(fixture, controller: controller)
            _ = try await fixture.run(pipeline: pipeline)
            #expect(controller.isAvailable)
            let next = WritingDeliveryAccess()
            fixture.enhancement.failure = WritingPipelineGenerationError.expected
            let failed = try await fixture.run(pipeline: pipeline, access: next)
            #expect(failed.transcriptionState == .failed)
            #expect(next.attempts == 0)
            #expect(controller.isAvailable && !controller.isBusy)
            #expect(await controller.undo().didRestoreText)
            #expect(fixture.access.value == "prefix old suffix")
            #expect(next.value == "prefix old suffix" && next.attempts == 0)
        }

        @Test @MainActor func supersededProviderCompletionCannotWriteOrReplaceTheNewerReceipt() async throws {
            let fixture = try WritingDeliveryFixture()
            defer { fixture.close() }
            let controller = WritingActionUndoController()
            let pipeline = Self.pipeline(fixture, controller: controller)
            let gate = WritingDeliveryGate()
            defer { gate.release() }
            fixture.enhancement.gate = gate
            let older = Task { try await fixture.run(pipeline: pipeline) }
            do { try await gate.waitUntilEntered() }
            catch { gate.release(); _ = try? await older.value; throw error }
            fixture.enhancement.gate = nil
            let newerAccess = WritingDeliveryAccess()
            let newer: Transcription
            do { newer = try await fixture.run(pipeline: pipeline, access: newerAccess) }
            catch { gate.release(); _ = try? await older.value; throw error }
            #expect(newer.transcriptionState == .completed)
            #expect(newerAccess.attempts == 1)
            #expect(controller.isAvailable)
            gate.release()
            let canceled = try await older.value
            #expect(canceled.transcriptionState == .canceled)
            #expect(fixture.access.attempts == 0)
            #expect(controller.isAvailable && !controller.isBusy)
            #expect(await controller.undo().didRestoreText)
            #expect(newerAccess.value == "prefix old suffix" && newerAccess.attempts == 2)
            #expect(fixture.access.attempts == 0)
        }

        @Test @MainActor func historySaveFailureAfterDeliveryReportsFailureWithoutReplayOrLosingUndo() async throws {
            let fixture = try WritingDeliveryFixture(readOnly: true)
            defer { fixture.close() }
            let controller = WritingActionUndoController()
            let pipeline = Self.pipeline(fixture, controller: controller)
            let record = try await fixture.run(pipeline: pipeline)
            #expect(fixture.access.value.utf16.elementsEqual(fixture.expectedDocument.utf16))
            #expect(fixture.access.attempts == 1)
            #expect(record.transcriptionState == .completed)
            #expect(record.text == fixture.instruction)
            #expect(record.enhancedText == fixture.enhancement.output)
            #expect(record.aiRequestSystemMessage == "owned system request")
            #expect(fixture.saveFailures.count == 1)
            #expect(fixture.saveFailures.first?.contains("History") == true)
            #expect(controller.isAvailable && !controller.isBusy)
            let fresh = ModelContext(fixture.container)
            #expect(try fresh.fetch(FetchDescriptor<Transcription>()).isEmpty)
            #expect(await controller.undo().didRestoreText)
            #expect(fixture.access.value == "prefix old suffix" && fixture.access.attempts == 2)
        }

        @Test @MainActor func cancellationBeforeAnAttemptPreservesThePreviousUndoAndClearsUndeliveredOutput() async throws {
            let fixture = try WritingDeliveryFixture()
            defer { fixture.close() }
            let controller = WritingActionUndoController()
            let pipeline = Self.pipeline(fixture, controller: controller)
            _ = try await fixture.run(pipeline: pipeline)
            let nextAccess = WritingDeliveryAccess()
            let gate = WritingDeliveryGate()
            defer { gate.release() }
            fixture.enhancement.gate = gate
            let work = Task { try await fixture.run(pipeline: pipeline, access: nextAccess) }
            do { try await gate.waitUntilEntered() }
            catch { gate.release(); _ = try? await work.value; throw error }
            #expect(controller.isBusy && !controller.isAvailable)
            let pending: Transcription
            do { pending = try #require(fixture.context.fetch(FetchDescriptor<Transcription>()).first { $0.transcriptionState == .pending }) }
            catch { gate.release(); _ = try? await work.value; throw error }
            pipeline.cancelDelivery(for: pending.id)
            gate.release()
            let canceled = try await work.value
            #expect(canceled.transcriptionState == .canceled)
            #expect(canceled.enhancedText == nil && canceled.aiRequestSystemMessage == nil)
            #expect(nextAccess.attempts == 0)
            #expect(fixture.enhancement.sawCancellationAfterGate)
            #expect(controller.isAvailable && !controller.isBusy)
            #expect(await controller.undo().didRestoreText)
            #expect(fixture.access.value == "prefix old suffix")
            #expect(nextAccess.value == "prefix old suffix" && nextAccess.attempts == 0)
        }

        @Test @MainActor func taskCancellationAtConfirmedDeliveryCannotEraseMetadataOrUndo() async throws {
            let fixture = try WritingDeliveryFixture()
            defer { fixture.close() }
            let controller = WritingActionUndoController()
            let pipeline = Self.pipeline(fixture, controller: controller)
            var work: Task<Transcription, Error>?
            fixture.access.afterMutation = { work?.cancel() }
            let task = Task { try await fixture.run(pipeline: pipeline) }
            work = task
            let record = try await task.value
            #expect(task.isCancelled)
            #expect(record.transcriptionState == .completed)
            #expect(record.enhancedText == fixture.enhancement.output)
            #expect(record.aiRequestSystemMessage == "owned system request")
            #expect(fixture.access.value.utf16.elementsEqual(fixture.expectedDocument.utf16))
            #expect(fixture.access.attempts == 1 && fixture.cancellations == 0)
            #expect(controller.isAvailable)
            fixture.access.afterMutation = nil
            #expect(await controller.undo().didRestoreText)
            #expect(fixture.access.value == "prefix old suffix" && fixture.access.attempts == 2)
        }

        @Test @MainActor func delayedAutoSendDistinguishesNormalCleanupCancellationAndNewerDelivery() async throws {
            let fixture = try WritingDeliveryFixture()
            defer { fixture.close() }
            let savedMode = PowerModeManager.shared.activeConfiguration
            let savedPasteMethod = UserDefaults.standard.object(forKey: VoiceInkPasteMethod.userDefaultsKey)
            defer {
                PowerModeManager.shared.activeConfiguration = savedMode
                if let savedPasteMethod { UserDefaults.standard.set(savedPasteMethod, forKey: VoiceInkPasteMethod.userDefaultsKey) }
                else { UserDefaults.standard.removeObject(forKey: VoiceInkPasteMethod.userDefaultsKey) }
                CursorPaster.configureAccessibilityTextInserterForTesting()
            }
            PowerModeManager.shared.activeConfiguration = PowerModeConfig(
                name: "Owned auto-send fixture", emoji: "", isAIEnhancementEnabled: false, autoSendKey: .enter
            )
            VoiceInkPasteMethod.setCurrent(.standard)
            var pasteAttempts = 0
            CursorPaster.configureAccessibilityTextInserterForTesting { _, _ in pasteAttempts += 1; return .inserted }
            var sent: [VoiceInkAutoSendKey] = []
            let controller = WritingActionUndoController()
            let pipeline = TranscriptionPipeline(
                modelContext: fixture.context, serviceRegistry: fixture.registry, enhancementService: nil,
                writingActionUndoController: controller, autoSend: { sent.append($0) }
            )
            for scenario in 0..<4 {
                var runIsActive = true
                var canceled = false
                let before = sent.count
                let record = Transcription(text: "", duration: 1)
                fixture.context.insert(record)
                let dismissal = WritingDeliveryGate()
                let work = Task {
                    await pipeline.run(
                        transcription: record, audioURL: fixture.directory.appendingPathComponent("auto-send.wav"),
                        model: TranscriptionModelRegistry.defaultMacOSFluidAudioModel,
                        session: UndoPipelineOrdinaryRecognizer(), cleanupProfile: VoiceInkDictationProfile.none,
                        latencyTraceToken: nil, onStateChange: { _ in },
                        shouldCancel: { canceled || !runIsActive }, onCancel: { Issue.record("The already delivered ordinary result was canceled.") },
                        onDismiss: {
                            if scenario == 1 { canceled = true }
                            if scenario == 3 { await dismissal.enter() }
                        }
                    )
                }
                if scenario == 3 {
                    do { try await dismissal.waitUntilEntered() }
                    catch { dismissal.release(); await work.value; throw error }
                    work.cancel()
                    do { try await Task.sleep(for: .milliseconds(300)) }
                    catch { dismissal.release(); await work.value; throw error }
                    #expect(sent.count == before, "Canceling the parent task while dismissal waits must suppress queued Enter before the operation exits.")
                    dismissal.release()
                }
                await work.value
                #expect(record.transcriptionState == .completed)
                // Mirrors successful engine cleanup, which releases this run's identity after return.
                runIsActive = false
                let newer = scenario == 2 ? controller.beginDelivery(transcriptionID: UUID()) : nil
                try await Task.sleep(for: .milliseconds(300))
                await Task.yield()
                if scenario == 0 { #expect(sent.count == before + 1 && sent.last == .enter) }
                else { #expect(sent.count == before, "Cancellation or a newer pending delivery must suppress the old queued Enter.") }
                if let newer { controller.finishDelivery(.notAttempted(CancellationError()), for: newer) }
            }
            #expect(pasteAttempts == 4)
        }

        @MainActor private static func pipeline(_ fixture: WritingDeliveryFixture, controller: WritingActionUndoController) -> TranscriptionPipeline {
            TranscriptionPipeline(
                modelContext: fixture.context, serviceRegistry: fixture.registry, enhancementService: fixture.enhancement,
                writingActionUndoController: controller,
                reportProcessingFailure: { fixture.notices.append($0) },
                reportWritingSaveFailure: { fixture.saveFailures.append($0) }
            )
        }
    }
}

private enum WritingPipelineGenerationError: Error { case expected }

@MainActor
private final class UndoPipelineOrdinaryRecognizer: TranscriptionSession {
    func prepare(model: any TranscriptionModel, latencyTraceToken: VoiceInkLatencyTrace.Token?) async throws -> ((Data) -> Void)? { nil }
    func transcribe(audioURL: URL) async throws -> String { "owned ordinary output" }
    func cancel() {}
}
