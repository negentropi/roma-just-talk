import AudioToolbox
import Foundation

public enum VoiceInkStoredAudioCodecError: Error, Equatable {
    case audioToolbox(operation: String, status: OSStatus)
    case emptyOutput
}

/// Stored recordings live as 16 kHz mono Opus in CAF. Transcription engines and
/// cloud uploads take PCM16 WAV, so they decode a temporary WAV when they need one.
public enum VoiceInkStoredAudioCodec {
    public static let opusFileExtension = "caf"
    public static let wavFileExtension = "wav"
    public static let opusBitRate: UInt32 = 16_000

    private static let framesPerChunk: UInt32 = 4_096

    public static func isWAV(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == wavFileExtension
    }

    /// Writes the Opus copy next to `wavURL` and returns its URL. The WAV stays in place.
    public static func encodeOpusSibling(
        of wavURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let opusURL = wavURL.deletingPathExtension().appendingPathExtension(opusFileExtension)
        let partialURL = wavURL.deletingPathExtension().appendingPathExtension("\(opusFileExtension).partial")
        try? fileManager.removeItem(at: partialURL)
        do {
            try encodeOpus(from: wavURL, to: partialURL)
            try? fileManager.removeItem(at: opusURL)
            try fileManager.moveItem(at: partialURL, to: opusURL)
        } catch {
            try? fileManager.removeItem(at: partialURL)
            throw error
        }
        return opusURL
    }

    public static func encodeOpus(from sourceURL: URL, to destinationURL: URL) throws {
        let clientFormat = monoFloat32Format()
        let reader = try openReader(sourceURL, clientFormat: clientFormat)
        defer { ExtAudioFileDispose(reader) }

        var opusFormat = AudioStreamBasicDescription(
            mSampleRate: VoiceInkPCM16Audio.mono16kSampleRate,
            mFormatID: kAudioFormatOpus,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 0,
            mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(VoiceInkPCM16Audio.monoChannelCount),
            mBitsPerChannel: 0,
            mReserved: 0
        )
        var writerRef: ExtAudioFileRef?
        try check("ExtAudioFileCreateWithURL", ExtAudioFileCreateWithURL(
            destinationURL as CFURL,
            kAudioFileCAFType,
            &opusFormat,
            nil,
            AudioFileFlags.eraseFile.rawValue,
            &writerRef
        ))
        guard let writer = writerRef else {
            throw VoiceInkStoredAudioCodecError.audioToolbox(operation: "ExtAudioFileCreateWithURL", status: -1)
        }
        var writerDisposed = false
        defer { if !writerDisposed { ExtAudioFileDispose(writer) } }

        // Without a reserve hint the CAF writer pads ahead of the audio data by
        // tens to hundreds of KB, which can exceed the Opus payload of a short dictation.
        var audioFileRef: AudioFileID?
        var audioFileSize = UInt32(MemoryLayout<AudioFileID?>.size)
        try check("kExtAudioFileProperty_AudioFile", ExtAudioFileGetProperty(
            writer,
            kExtAudioFileProperty_AudioFile,
            &audioFileSize,
            &audioFileRef
        ))
        if let audioFileRef {
            var reserveDuration: Float64 = 0
            try check("kAudioFilePropertyReserveDuration", AudioFileSetProperty(
                audioFileRef,
                kAudioFilePropertyReserveDuration,
                UInt32(MemoryLayout<Float64>.size),
                &reserveDuration
            ))
        }

        try setClientFormat(clientFormat, on: writer)
        try setEncoderBitRate(opusBitRate, on: writer)

        var framesWritten: UInt64 = 0
        try readChunks(from: reader, clientFormat: clientFormat) { bufferList, frameCount in
            try check("ExtAudioFileWrite", ExtAudioFileWrite(writer, frameCount, bufferList))
            framesWritten += UInt64(frameCount)
        }

        writerDisposed = true
        try check("ExtAudioFileDispose", ExtAudioFileDispose(writer))
        guard framesWritten > 0 else {
            throw VoiceInkStoredAudioCodecError.emptyOutput
        }
    }

    /// Decodes any readable audio file to the 16 kHz mono PCM16 WAV the transcription engines read.
    public static func decodePCM16WAV(from sourceURL: URL, to destinationURL: URL) throws {
        let clientFormat = monoPCM16Format()
        let reader = try openReader(sourceURL, clientFormat: clientFormat)
        defer { ExtAudioFileDispose(reader) }

        var pcmData = Data()
        try readChunks(from: reader, clientFormat: clientFormat) { bufferList, _ in
            let buffer = bufferList.pointee.mBuffers
            if let bytes = buffer.mData {
                pcmData.append(bytes.assumingMemoryBound(to: UInt8.self), count: Int(buffer.mDataByteSize))
            }
        }
        guard !pcmData.isEmpty else {
            throw VoiceInkStoredAudioCodecError.emptyOutput
        }
        try VoiceInkPCM16Audio.wavData(fromLittleEndianPCM16Data: pcmData).write(to: destinationURL, options: .atomic)
    }

    /// Runs `body` with a PCM16 WAV of `url`, decoding to a temporary file when `url` is not a WAV.
    public static func withPCM16WAV<T>(
        for url: URL,
        fileManager: FileManager = .default,
        _ body: (URL) async throws -> T
    ) async throws -> T {
        guard !isWAV(url) else {
            return try await body(url)
        }
        let wavURL = fileManager.temporaryDirectory
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-\(UUID().uuidString)")
            .appendingPathExtension(wavFileExtension)
        defer { try? fileManager.removeItem(at: wavURL) }
        try await Task.detached(priority: .userInitiated) {
            try decodePCM16WAV(from: url, to: wavURL)
        }.value
        return try await body(wavURL)
    }

    private static func monoFloat32Format() -> AudioStreamBasicDescription {
        let bytesPerFrame = UInt32(MemoryLayout<Float32>.size * VoiceInkPCM16Audio.monoChannelCount)
        return AudioStreamBasicDescription(
            mSampleRate: VoiceInkPCM16Audio.mono16kSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: bytesPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: UInt32(VoiceInkPCM16Audio.monoChannelCount),
            mBitsPerChannel: 32,
            mReserved: 0
        )
    }

    private static func monoPCM16Format() -> AudioStreamBasicDescription {
        let bytesPerFrame = UInt32(VoiceInkPCM16Audio.bytesPerSample * VoiceInkPCM16Audio.monoChannelCount)
        return AudioStreamBasicDescription(
            mSampleRate: VoiceInkPCM16Audio.mono16kSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: bytesPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: UInt32(VoiceInkPCM16Audio.monoChannelCount),
            mBitsPerChannel: UInt32(VoiceInkPCM16Audio.bitsPerSample),
            mReserved: 0
        )
    }

    private static func openReader(
        _ url: URL,
        clientFormat: AudioStreamBasicDescription
    ) throws -> ExtAudioFileRef {
        var readerRef: ExtAudioFileRef?
        try check("ExtAudioFileOpenURL", ExtAudioFileOpenURL(url as CFURL, &readerRef))
        guard let reader = readerRef else {
            throw VoiceInkStoredAudioCodecError.audioToolbox(operation: "ExtAudioFileOpenURL", status: -1)
        }
        do {
            try setClientFormat(clientFormat, on: reader)
        } catch {
            ExtAudioFileDispose(reader)
            throw error
        }
        return reader
    }

    private static func setClientFormat(
        _ format: AudioStreamBasicDescription,
        on file: ExtAudioFileRef
    ) throws {
        var format = format
        try check("kExtAudioFileProperty_ClientDataFormat", ExtAudioFileSetProperty(
            file,
            kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
            &format
        ))
    }

    private static func setEncoderBitRate(_ bitRate: UInt32, on file: ExtAudioFileRef) throws {
        var converterRef: AudioConverterRef?
        var converterSize = UInt32(MemoryLayout<AudioConverterRef?>.size)
        try check("kExtAudioFileProperty_AudioConverter", ExtAudioFileGetProperty(
            file,
            kExtAudioFileProperty_AudioConverter,
            &converterSize,
            &converterRef
        ))
        guard let converterRef else { return }
        var bitRate = bitRate
        try check("kAudioConverterEncodeBitRate", AudioConverterSetProperty(
            converterRef,
            kAudioConverterEncodeBitRate,
            UInt32(MemoryLayout<UInt32>.size),
            &bitRate
        ))
        // ExtAudioFile only picks up converter changes after its config is reset.
        var config: CFArray?
        let status = withUnsafeMutablePointer(to: &config) { pointer in
            ExtAudioFileSetProperty(
                file,
                kExtAudioFileProperty_ConverterConfig,
                UInt32(MemoryLayout<CFArray?>.size),
                pointer
            )
        }
        try check("kExtAudioFileProperty_ConverterConfig", status)
    }

    private static func readChunks(
        from reader: ExtAudioFileRef,
        clientFormat: AudioStreamBasicDescription,
        _ consume: (UnsafePointer<AudioBufferList>, UInt32) throws -> Void
    ) throws {
        let byteCapacity = Int(framesPerChunk * clientFormat.mBytesPerFrame)
        let storage = UnsafeMutableRawPointer.allocate(byteCount: byteCapacity, alignment: 16)
        defer { storage.deallocate() }

        while true {
            var bufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: clientFormat.mChannelsPerFrame,
                    mDataByteSize: UInt32(byteCapacity),
                    mData: storage
                )
            )
            var frameCount = framesPerChunk
            try check("ExtAudioFileRead", ExtAudioFileRead(reader, &frameCount, &bufferList))
            guard frameCount > 0 else { return }
            try consume(&bufferList, frameCount)
        }
    }

    private static func check(_ operation: String, _ status: OSStatus) throws {
        guard status == noErr else {
            throw VoiceInkStoredAudioCodecError.audioToolbox(operation: operation, status: status)
        }
    }
}

public enum VoiceInkStoredAudioCompression {
    /// Replaces the record's stored WAV with an Opus copy once nothing else needs the WAV.
    /// Returns the Opus URL, or nil when the record has no stored WAV or changed while encoding.
    /// Any failure leaves the record pointing at its WAV.
    @MainActor
    @discardableResult
    public static func compressStoredWAV<Record: VoiceInkStoredAudioRecord>(
        of record: Record,
        isLive: (Record) -> Bool,
        save: () throws -> Void,
        fileManager: FileManager = .default
    ) async throws -> URL? {
        guard let storedValue = record.audioFileURL,
              let wavURL = record.existingAudioFileURL(fileManager: fileManager),
              VoiceInkStoredAudioCodec.isWAV(wavURL) else {
            return nil
        }

        let opusURL = try await Task.detached(priority: .utility) {
            try VoiceInkStoredAudioCodec.encodeOpusSibling(of: wavURL, fileManager: fileManager)
        }.value

        // The record can be deleted, cleaned up, or repointed while encoding runs.
        guard isLive(record), record.audioFileURL == storedValue else {
            try? fileManager.removeItem(at: opusURL)
            return nil
        }

        record.audioFileURL = opusURL.absoluteString
        do {
            try save()
        } catch {
            record.audioFileURL = storedValue
            try? fileManager.removeItem(at: opusURL)
            throw error
        }
        try? fileManager.removeItem(at: wavURL)
        return opusURL
    }
}
