
import Foundation
import AppKit
import SwiftData
import RomaCore

class RomaCSVExportService {
    
    func exportTranscriptionsToCSV(transcriptions: [Transcription]) {
        let csvString = RomaTranscriptionCSVExporter.csvString(
            for: transcriptions.map { RomaTranscriptionCSVRecord(transcription: $0) }
        )
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = RomaTranscriptionCSVExporter.defaultFilename
        
        savePanel.begin { result in
            if result == .OK, let url = savePanel.url {
                do {
                    try csvString.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print(RomaTranscriptionCSVExporter.writeFailureDiagnosticMessage(errorDescription: String(describing: error)))
                }
            }
        }
    }
}

private extension RomaTranscriptionCSVRecord {
    init(transcription: Transcription) {
        self.init(
            originalText: transcription.text,
            enhancedText: transcription.enhancedText,
            enhancementModel: transcription.aiEnhancementModelName,
            promptName: transcription.promptName,
            transcriptionModel: transcription.transcriptionModelName,
            powerModeName: transcription.powerModeName,
            powerModeEmoji: transcription.powerModeEmoji,
            enhancementTime: transcription.enhancementDuration,
            transcriptionTime: transcription.transcriptionDuration,
            timestamp: transcription.timestamp,
            duration: transcription.duration
        )
    }
}
