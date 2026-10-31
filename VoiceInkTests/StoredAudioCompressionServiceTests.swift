import AVFoundation
import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

@Suite(.serialized)
struct StoredAudioCompressionServiceTests {
    @Test @MainActor func createdTranscriptionSwapsItsWAVForOpus() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoredAudioCompressionServiceTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sampleRate = VoiceInkPCM16Audio.mono16kSampleRate
        var pcm = Data()
        for index in 0..<Int(sampleRate * 2) {
            let sample = Int16(8_000 * sin(2 * .pi * 220 * Double(index) / sampleRate))
            withUnsafeBytes(of: sample.littleEndian) { pcm.append(contentsOf: $0) }
        }
        let wavURL = VoiceInkStoredAudioFile.recordingFileURL(in: directory)
        try VoiceInkPCM16Audio.wavData(fromLittleEndianPCM16Data: pcm).write(to: wavURL)

        let schema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let transcription = Transcription(
            text: "hello",
            duration: 2,
            audioFileURL: wavURL.absoluteString,
            transcriptionStatus: .completed
        )
        container.mainContext.insert(transcription)
        try container.mainContext.save()

        StoredAudioCompressionService.shared.startMonitoring()
        NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)

        let deadline = Date().addingTimeInterval(20)
        while transcription.audioFileURL == wavURL.absoluteString, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let opusURL = try #require(transcription.existingAudioFileURL())
        #expect(opusURL.pathExtension == "caf")
        #expect(!FileManager.default.fileExists(atPath: wavURL.path))
        #expect(!container.mainContext.hasChanges)
        let opusFile = try AVAudioFile(forReading: opusURL)
        #expect(opusFile.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatOpus)
        #expect(abs(try AVAudioPlayer(contentsOf: opusURL).duration - 2) < 0.05)
    }

    @Test @MainActor func launchConvertsWAVsSavedBeforeItAndLeavesNewerRecordingsAlone() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoredAudioCompressionServiceTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let schema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = container.mainContext
        func insertRow(status: VoiceInkTranscriptionStatus) throws -> (Transcription, URL) {
            let wavURL = VoiceInkStoredAudioFile.recordingFileURL(in: directory)
            try Self.toneWAV(seconds: 1).write(to: wavURL)
            let row = Transcription(text: "hello", duration: 1, audioFileURL: wavURL.absoluteString, transcriptionStatus: status)
            context.insert(row)
            return (row, wavURL)
        }

        let (completed, completedWAV) = try insertRow(status: .completed)
        let (canceled, canceledWAV) = try insertRow(status: .canceled)
        let missing = Transcription(text: "gone", duration: 1, audioFileURL: directory.appendingPathComponent("missing.wav").absoluteString, transcriptionStatus: .completed)
        context.insert(missing)
        try context.save()
        let launchDate = Date()
        let (inFlight, inFlightWAV) = try insertRow(status: .pending)
        try context.save()

        let converted = await StoredAudioCompressionService.shared.compressExistingRecordings(in: context, createdBefore: launchDate)

        #expect(converted == 2)
        for (row, wavURL) in [(completed, completedWAV), (canceled, canceledWAV)] {
            let opusURL = try #require(row.existingAudioFileURL())
            #expect(opusURL.pathExtension == "caf")
            #expect(!FileManager.default.fileExists(atPath: wavURL.path))
            let opusFile = try AVAudioFile(forReading: opusURL)
            #expect(opusFile.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatOpus)
        }
        #expect(inFlight.audioFileURL == inFlightWAV.absoluteString)
        #expect(FileManager.default.fileExists(atPath: inFlightWAV.path))
        #expect(missing.audioFileURL?.hasSuffix("missing.wav") == true)
        #expect(!context.hasChanges)

        #expect(await StoredAudioCompressionService.shared.compressExistingRecordings(in: context, createdBefore: launchDate) == 0)
    }

    private static func toneWAV(seconds: Double) -> Data {
        let sampleRate = VoiceInkPCM16Audio.mono16kSampleRate
        var pcm = Data()
        for index in 0..<Int(sampleRate * seconds) {
            let sample = Int16(8_000 * sin(2 * .pi * 220 * Double(index) / sampleRate))
            withUnsafeBytes(of: sample.littleEndian) { pcm.append(contentsOf: $0) }
        }
        return VoiceInkPCM16Audio.wavData(fromLittleEndianPCM16Data: pcm)
    }
}
