import CoreTransferable
import Foundation
import UniformTypeIdentifiers
import VoiceInkCore

struct VoiceInkIOSCSVExport: Transferable {
    let csvString: String

    init(transcriptions: [Transcription]) {
        csvString = VoiceInkTranscriptionCSVExporter.csvString(
            for: transcriptions.map(VoiceInkTranscriptionCSVRecord.init)
        )
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(VoiceInkTranscriptionCSVExporter.defaultFilename)
            try export.csvString.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

private extension VoiceInkTranscriptionCSVRecord {
    init(_ transcription: Transcription) {
        self.init(
            originalText: transcription.text,
            enhancedText: transcription.enhancedText,
            enhancementModel: transcription.aiEnhancementModelName,
            promptName: transcription.promptName,
            transcriptionModel: transcription.transcriptionModelName,
            enhancementTime: transcription.enhancementDuration,
            transcriptionTime: transcription.transcriptionDuration,
            timestamp: transcription.timestamp,
            duration: transcription.duration
        )
    }
}
