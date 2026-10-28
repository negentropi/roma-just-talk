import AVFoundation
import Foundation
import VoiceInkCore

final class StoredAudioCodecTests: XCTestCase {
    private final class StoredAudioRecordFixture: VoiceInkStoredAudioRecord {
        var audioFileURL: String?

        init(audioFileURL: String?) {
            self.audioFileURL = audioFileURL
        }
    }

    private struct SaveFailure: Error {}

    @MainActor
    func testStoredWAVBecomesSmallOpusThatPlaysBackAtTheSameDuration() async throws {
        let directory = try makeRecordingsDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let wavURL = try writeSpeechLikeWAV(seconds: 6, in: directory)
        let wavSize = try fileSize(wavURL)
        let record = StoredAudioRecordFixture(audioFileURL: wavURL.absoluteString)
        var saveCount = 0

        let compressedURL = try await VoiceInkStoredAudioCompression.compressStoredWAV(
            of: record,
            isLive: { _ in true },
            save: { saveCount += 1 }
        )
        let opusURL = try XCTUnwrap(compressedURL)

        XCTAssertEqual(record.audioFileURL, opusURL.absoluteString)
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(opusURL.pathExtension, "caf")
        XCTAssertFalse(FileManager.default.fileExists(atPath: wavURL.path), "WAV removed after the record moved to Opus")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [opusURL.lastPathComponent])

        let opusFile = try AVAudioFile(forReading: opusURL)
        XCTAssertEqual(opusFile.fileFormat.streamDescription.pointee.mFormatID, kAudioFormatOpus)
        XCTAssertEqual(opusFile.fileFormat.channelCount, 1)
        XCTAssertEqual(Double(opusFile.length) / opusFile.fileFormat.sampleRate, 6, accuracy: 0.05)
        let opusSize = try fileSize(opusURL)
        XCTAssertLessThan(opusSize * 8, wavSize, "Opus \(opusSize) bytes vs WAV \(wavSize) bytes")

        let player = try AVAudioPlayer(contentsOf: opusURL)
        XCTAssertEqual(player.duration, 6, accuracy: 0.05)
    }

    func testStoredOpusDecodesToTheWAVTheEnginesAndCloudUploadsRead() async throws {
        let directory = try makeRecordingsDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let wavURL = try writeSpeechLikeWAV(seconds: 3, in: directory)
        let opusURL = try VoiceInkStoredAudioCodec.encodeOpusSibling(of: wavURL)
        let originalSamples = try XCTUnwrap(try VoiceInkPCM16Audio.floatSamples(fromWAVFileAt: wavURL))

        XCTAssertNil(try VoiceInkPCM16Audio.floatSamples(fromWAVFileAt: opusURL), "engines cannot read Opus directly")

        var decodedURL: URL?
        let decodedSamples = try await VoiceInkStoredAudioCodec.withPCM16WAV(for: opusURL) { url in
            decodedURL = url
            XCTAssertEqual(try VoiceInkCloudTranscriptionAudioFile.load(from: url).fileName.hasSuffix(".wav"), true)
            return try VoiceInkPCM16Audio.floatSamples(fromWAVFileAt: url)
        }

        XCTAssertEqual(Double(try XCTUnwrap(decodedSamples).count), Double(originalSamples.count), accuracy: 16)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(decodedURL).path), "temporary WAV removed")

        var passedThroughURL: URL?
        try await VoiceInkStoredAudioCodec.withPCM16WAV(for: wavURL) { passedThroughURL = $0 }
        XCTAssertEqual(passedThroughURL, wavURL)
    }

    @MainActor
    func testFailedSaveKeepsTheRecordOnItsWAV() async throws {
        let directory = try makeRecordingsDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let wavURL = try writeSpeechLikeWAV(seconds: 1, in: directory)
        let record = StoredAudioRecordFixture(audioFileURL: wavURL.absoluteString)

        do {
            try await VoiceInkStoredAudioCompression.compressStoredWAV(
                of: record,
                isLive: { _ in true },
                save: { throw SaveFailure() }
            )
            XCTFail("save failure propagates")
        } catch is SaveFailure {}

        XCTAssertEqual(record.audioFileURL, wavURL.absoluteString)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [wavURL.lastPathComponent])
    }

    @MainActor
    func testRecordChangedDuringEncodingKeepsItsCurrentAudio() async throws {
        let directory = try makeRecordingsDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let wavURL = try writeSpeechLikeWAV(seconds: 1, in: directory)
        let record = StoredAudioRecordFixture(audioFileURL: wavURL.absoluteString)

        let result = try await VoiceInkStoredAudioCompression.compressStoredWAV(
            of: record,
            isLive: { _ in false },
            save: { XCTFail("deleted record is not saved") }
        )

        XCTAssertNil(result)
        XCTAssertEqual(record.audioFileURL, wavURL.absoluteString)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [wavURL.lastPathComponent])
    }

    @MainActor
    func testUnreadableWAVAndNonWAVRecordsAreLeftAlone() async throws {
        let directory = try makeRecordingsDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let brokenURL = directory.appendingPathComponent("broken.wav")
        try Data("not audio".utf8).write(to: brokenURL)
        let brokenRecord = StoredAudioRecordFixture(audioFileURL: brokenURL.absoluteString)

        do {
            try await VoiceInkStoredAudioCompression.compressStoredWAV(
                of: brokenRecord,
                isLive: { _ in true },
                save: { XCTFail("failed encode is not saved") }
            )
            XCTFail("unreadable WAV throws")
        } catch is VoiceInkStoredAudioCodecError {}
        XCTAssertEqual(brokenRecord.audioFileURL, brokenURL.absoluteString)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["broken.wav"])

        let opusRecord = StoredAudioRecordFixture(audioFileURL: directory.appendingPathComponent("a.caf").absoluteString)
        try Data().write(to: directory.appendingPathComponent("a.caf"))
        let missingRecord = StoredAudioRecordFixture(audioFileURL: directory.appendingPathComponent("gone.wav").absoluteString)
        for record in [opusRecord, missingRecord] {
            let result = try await VoiceInkStoredAudioCompression.compressStoredWAV(
                of: record,
                isLive: { _ in true },
                save: { XCTFail("nothing to compress") }
            )
            XCTAssertNil(result)
        }
    }

    private func makeRecordingsDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.StoredAudioCodecTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Voiced harmonics under a syllable-rate envelope plus light noise, so Opus sees speech-like input.
    private func writeSpeechLikeWAV(seconds: Double, in directory: URL) throws -> URL {
        let sampleRate = VoiceInkPCM16Audio.mono16kSampleRate
        let sampleCount = Int(sampleRate * seconds)
        var pcm = Data(capacity: sampleCount * VoiceInkPCM16Audio.bytesPerSample)
        var seed: UInt32 = 1
        var phase = 0.0
        for index in 0..<sampleCount {
            let time = Double(index) / sampleRate
            phase += 2 * .pi * (120 + 30 * sin(2 * .pi * 0.7 * time)) / sampleRate
            var voiced = 0.0
            for harmonic in 1...12 {
                voiced += sin(phase * Double(harmonic)) / Double(harmonic)
            }
            let envelope = max(0, sin(2 * .pi * 2.5 * time))
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = Double(Int32(bitPattern: seed)) / Double(Int32.max) * 0.03
            let sample = Int16(clamping: Int((voiced * 0.3 * envelope + noise) * 12_000))
            withUnsafeBytes(of: sample.littleEndian) { pcm.append(contentsOf: $0) }
        }
        let url = VoiceInkStoredAudioFile.recordingFileURL(in: directory)
        try VoiceInkPCM16Audio.wavData(fromLittleEndianPCM16Data: pcm).write(to: url)
        return url
    }

    private func fileSize(_ url: URL) throws -> Int {
        try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
    }
}
