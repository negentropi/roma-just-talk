import CoreTransferable
import Foundation
import UniformTypeIdentifiers
import RomaCore

struct RomaIOSCSVExport: Transferable {
    let csvString: String

    init(transcriptions: [Transcription]) {
        csvString = RomaTranscriptionCSVExporter.csvString(
            for: transcriptions.map(RomaTranscriptionCSVRecord.init)
        )
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(RomaTranscriptionCSVExporter.defaultFilename)
            try export.csvString.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

private extension RomaTranscriptionCSVRecord {
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
