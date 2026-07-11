import AVFoundation
import Combine
import Foundation
import SwiftData
import VoiceInkCore

enum VoiceInkIOSAudioImportError: LocalizedError {
    case noAudioTrack
    case readerFailed(String)
    case unsupportedFile

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "The selected file does not contain an audio track."
        case .readerFailed(let message):
            return "The audio could not be prepared: \(message)"
        case .unsupportedFile:
            return "This file type is not supported."
        }
    }
}

struct VoiceInkIOSPreparedAudio: Sendable {
    let sourcePath: String
    let filename: String
    let storedURL: URL
    let duration: TimeInterval
}

enum VoiceInkIOSAudioImportPreparer {
    static let sampleRate = 16_000
    static let channelCount = 1
    static let bitsPerSample = 16

    static func prepare(_ sourceURL: URL) async throws -> VoiceInkIOSPreparedAudio {
        guard VoiceInkSupportedMedia.isSupported(url: sourceURL) else {
            throw VoiceInkIOSAudioImportError.unsupportedFile
        }

        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let asset = AVURLAsset(url: sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw VoiceInkIOSAudioImportError.noAudioTrack
        }
        let duration = try await asset.load(.duration).seconds
        let recordingsDirectory = try VoiceInkStoredAudioFile.createRecordingsDirectory(
            in: VoiceInkIOSStorageDirectories.documentsDirectory
        )
        let destinationURL = VoiceInkStoredAudioFile.importedTranscriptionFileURL(
            in: recordingsDirectory
        )

        do {
            try writePCM16WAV(asset: asset, track: track, to: destinationURL)
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }

        return VoiceInkIOSPreparedAudio(
            sourcePath: sourceURL.standardizedFileURL.path,
            filename: sourceURL.lastPathComponent,
            storedURL: destinationURL,
            duration: duration.isFinite ? max(0, duration) : 0
        )
    }

    private static func writePCM16WAV(
        asset: AVAsset,
        track: AVAssetTrack,
        to destinationURL: URL
    ) throws {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVLinearPCMBitDepthKey: bitsPerSample,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw VoiceInkIOSAudioImportError.readerFailed("The audio track cannot be decoded.")
        }
        reader.add(output)

        FileManager.default.createFile(atPath: destinationURL.path, contents: Data(count: 44))
        let handle = try FileHandle(forWritingTo: destinationURL)
        defer { try? handle.close() }

        guard reader.startReading() else {
            throw VoiceInkIOSAudioImportError.readerFailed(
                reader.error?.localizedDescription ?? "The decoder did not start."
            )
        }

        var audioByteCount: UInt64 = 0
        while let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            guard length > 0 else { continue }
            var bytes = Data(count: length)
            let status = bytes.withUnsafeMutableBytes { destination in
                guard let address = destination.baseAddress else { return OSStatus(-1) }
                return CMBlockBufferCopyDataBytes(
                    blockBuffer,
                    atOffset: 0,
                    dataLength: length,
                    destination: address
                )
            }
            guard status == kCMBlockBufferNoErr else {
                reader.cancelReading()
                throw VoiceInkIOSAudioImportError.readerFailed("The decoded samples could not be read.")
            }
            try handle.write(contentsOf: bytes)
            audioByteCount += UInt64(length)
        }

        guard reader.status == .completed else {
            throw VoiceInkIOSAudioImportError.readerFailed(
                reader.error?.localizedDescription ?? "The decoder stopped early."
            )
        }
        guard audioByteCount <= UInt64(UInt32.max) - 36 else {
            throw VoiceInkIOSAudioImportError.readerFailed("The decoded audio is too large for WAV.")
        }

        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: wavHeader(audioByteCount: UInt32(audioByteCount)))
    }

    static func wavHeader(audioByteCount: UInt32) -> Data {
        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        appendLittleEndian(36 + audioByteCount, to: &data)
        data.append(contentsOf: "WAVEfmt ".utf8)
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(UInt16(channelCount), to: &data)
        appendLittleEndian(UInt32(sampleRate), to: &data)
        let byteRate = UInt32(sampleRate * channelCount * bitsPerSample / 8)
        appendLittleEndian(byteRate, to: &data)
        appendLittleEndian(UInt16(channelCount * bitsPerSample / 8), to: &data)
        appendLittleEndian(UInt16(bitsPerSample), to: &data)
        data.append(contentsOf: "data".utf8)
        appendLittleEndian(audioByteCount, to: &data)
        return data
    }

    private static func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}

@MainActor
final class VoiceInkIOSAudioImportQueueItem: ObservableObject, Identifiable {
    let id = UUID()
    let sourcePath: String
    let filename: String
    let storedURL: URL
    let duration: TimeInterval

    @Published var status: VoiceInkAudioFileQueueStatus = .pending
    @Published var transcription: Transcription?

    init(preparedAudio: VoiceInkIOSPreparedAudio) {
        sourcePath = preparedAudio.sourcePath
        filename = preparedAudio.filename
        storedURL = preparedAudio.storedURL
        duration = preparedAudio.duration
    }
}

@MainActor
final class IOSAudioImportManager: ObservableObject {
    static let shared = IOSAudioImportManager()

    @Published private(set) var queue: [VoiceInkIOSAudioImportQueueItem] = []
    @Published private(set) var isImporting = false
    @Published private(set) var isProcessingQueue = false
    @Published var isPresented = false
    @Published var importErrorMessage: String?

    private let transcriptionTasks: IOSTranscriptionTaskCoordinator
    private var processingTask: Task<Void, Never>?
    private var currentItemID: UUID?

    init(transcriptionTasks: IOSTranscriptionTaskCoordinator = .shared) {
        self.transcriptionTasks = transcriptionTasks
    }

    var hasPendingItems: Bool {
        VoiceInkAudioFileQueuePolicy.hasPendingItems(in: queueFacts)
    }

    func add(urls: [URL]) async {
        let candidates = urls.map {
            VoiceInkAudioFileQueueCandidate(
                url: $0,
                fileExists: FileManager.default.fileExists(atPath: $0.path),
                isSupported: VoiceInkSupportedMedia.isSupported(url: $0)
            )
        }
        let eligibleURLs = VoiceInkAudioFileQueuePolicy.eligibleAdditionURLs(
            from: candidates,
            existingItems: queueFacts
        )
        guard !eligibleURLs.isEmpty else { return }

        isImporting = true
        isPresented = true
        defer { isImporting = false }

        for url in eligibleURLs {
            do {
                let prepared = try await Task.detached(priority: .userInitiated) {
                    try await VoiceInkIOSAudioImportPreparer.prepare(url)
                }.value
                queue.append(VoiceInkIOSAudioImportQueueItem(preparedAudio: prepared))
            } catch is CancellationError {
                return
            } catch {
                importErrorMessage = VoiceInkErrorDescription.text(for: error)
            }
        }
    }

    func removePendingItem(id: UUID) {
        guard VoiceInkAudioFileQueuePolicy.canRemoveItem(id: id, from: queueFacts),
              let index = queue.firstIndex(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: queue[index].storedURL)
        queue.remove(at: index)
    }

    func retryItem(id: UUID) {
        guard let item = queue.first(where: { $0.id == id }),
              let status = VoiceInkAudioFileQueuePolicy.statusAfterRetryRequest(item.status) else { return }
        item.status = status
    }

    func startProcessing(modelContext: ModelContext) {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true
        processingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, let item = self.nextPendingItem() {
                await self.process(item, modelContext: modelContext)
            }
            self.currentItemID = nil
            self.isProcessingQueue = false
        }
    }

    func cancelProcessing() {
        processingTask?.cancel()
        if let currentItemID,
           let noteID = queue.first(where: { $0.id == currentItemID })?.transcription?.id {
            transcriptionTasks.cancel(noteID: noteID)
        }
        for (item, status) in zip(
            queue,
            VoiceInkAudioFileQueuePolicy.statusesAfterCancelingProcessing(queue.map(\.status))
        ) {
            item.status = status
        }
    }

    func clearFinishedAndPendingItems() {
        guard !isProcessingQueue else { return }
        for item in queue where item.transcription == nil {
            try? FileManager.default.removeItem(at: item.storedURL)
        }
        queue.removeAll()
    }

    private var queueFacts: [VoiceInkAudioFileQueueItemFacts<UUID>] {
        queue.map {
            VoiceInkAudioFileQueueItemFacts(
                id: $0.id,
                standardizedPath: $0.sourcePath,
                status: $0.status
            )
        }
    }

    private func nextPendingItem() -> VoiceInkIOSAudioImportQueueItem? {
        guard let id = VoiceInkAudioFileQueuePolicy.nextPendingItemID(in: queueFacts) else { return nil }
        return queue.first { $0.id == id }
    }

    private func process(_ item: VoiceInkIOSAudioImportQueueItem, modelContext: ModelContext) async {
        currentItemID = item.id
        item.status = .processing(phase: .transcribing)

        let note: Transcription
        if let existing = item.transcription {
            note = existing
        } else {
            note = Transcription(
                text: "",
                duration: item.duration,
                audioFileURL: item.storedURL.lastPathComponent
            )
            item.transcription = note
            modelContext.insert(note)
            try? modelContext.save()
        }

        let outcome = await withCheckedContinuation { continuation in
            let gate = VoiceInkIOSAudioImportContinuationGate(continuation)
            let started = transcriptionTasks.start(
                note: note,
                persist: { try? modelContext.save() },
                completion: { gate.resume(returning: $0) }
            )
            if !started {
                gate.resume(returning: .failed(
                    reason: note.transcriptionError ?? "Transcription could not start."
                ))
            }
        }

        switch outcome {
        case .succeeded:
            item.status = .completed
        case .failed(let reason):
            item.status = .failed(message: reason)
        case .canceled:
            item.status = Task.isCancelled ? .pending : .failed(
                message: VoiceInkTranscriptPresentation.canceledTranscriptionText
            )
        }
    }
}

@MainActor
private final class VoiceInkIOSAudioImportContinuationGate {
    private var continuation: CheckedContinuation<VoiceInkStoredAudioRetranscriptionOutcome, Never>?

    init(_ continuation: CheckedContinuation<VoiceInkStoredAudioRetranscriptionOutcome, Never>) {
        self.continuation = continuation
    }

    func resume(returning outcome: VoiceInkStoredAudioRetranscriptionOutcome) {
        continuation?.resume(returning: outcome)
        continuation = nil
    }
}
