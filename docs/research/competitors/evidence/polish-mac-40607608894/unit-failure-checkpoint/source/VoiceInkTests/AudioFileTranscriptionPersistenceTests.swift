import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

extension VoiceInkTests {
    struct AudioFileTranscriptionPersistenceTests {
        @Test @MainActor func savingCompletedAudioDoesNotCommitUnrelatedCallerEdits() throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RJT-Audio-Persistence-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: directory) }
            let schema = Schema([Transcription.self, VocabularyWord.self])
            let configuration = ModelConfiguration("AudioPersistence", schema: schema,
                url: directory.appendingPathComponent("audio.store"), cloudKitDatabase: .none)
            try #require(configuration.allowsSave && !configuration.isStoredInMemoryOnly)
            try #require(configuration.groupAppContainerIdentifier == nil && configuration.cloudKitContainerIdentifier == nil)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let caller = container.mainContext
            caller.autosaveEnabled = false
            let bystander = VocabularyWord(word: "saved vocabulary")
            caller.insert(bystander)
            try caller.save()
            bystander.word = "unrelated unsaved edit"
            let exact = "  Saved e\u{301} 🧪\r\nexactly. "
            let draft = VoiceInkCompletedTranscriptionDraft(
                cleanedText: exact, duration: 2, audioFileURL: "file:///owned-audio.wav",
                transcriptionModelName: "captured model", transcriptionDuration: 0.5,
                recognitionText: exact, dictationProfile: VoiceInkDictationProfile.none)

            // Exercise the shared SwiftData writer without an ASR/provider or queue fixture.
            let savedID = try AudioFileTranscriptionPersistence.save(draft, in: container)
            let result = try #require(caller.model(for: savedID) as? Transcription)
            #expect(result.modelContext === caller)
            #expect(result.text.utf8.elementsEqual(exact.utf8))
            #expect(result.recognitionText?.utf16.elementsEqual(exact.utf16) == true)
            #expect(result.dictationProfile == VoiceInkDictationProfile.none)
            #expect(result.transcriptionState == .completed)
            #expect(result.audioFileURL == draft.audioFileURL)
            #expect(result.transcriptionModelName == "captured model" && result.transcriptionDuration == 0.5)
            #expect(try caller.fetch(FetchDescriptor<Transcription>()).map(\.id) == [result.id])
            #expect(bystander.word == "unrelated unsaved edit" && caller.hasChanges)

            let fresh = ModelContext(container)
            fresh.autosaveEnabled = false
            let persisted = try #require(fresh.fetch(FetchDescriptor<Transcription>()).first)
            #expect(persisted.id == result.id && persisted.persistentModelID == savedID)
            #expect(persisted.text.utf8.elementsEqual(exact.utf8))
            #expect(persisted.recognitionText?.utf16.elementsEqual(exact.utf16) == true)
            #expect(persisted.transcriptionState == .completed && persisted.dictationProfile == VoiceInkDictationProfile.none)
            #expect(try fresh.fetch(FetchDescriptor<VocabularyWord>()).map(\.word) == ["saved vocabulary"])
            #expect(bystander.word == "unrelated unsaved edit" && caller.hasChanges)
        }
    }
}
