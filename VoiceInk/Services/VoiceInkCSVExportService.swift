
import Foundation
import AppKit
import SwiftData
import VoiceInkCore

class VoiceInkCSVExportService {
    
    func exportTranscriptionsToCSV(transcriptions: [Transcription]) {
        let csvString = VoiceInkTranscriptionCSVExporter.csvString(
            for: transcriptions.map { VoiceInkTranscriptionCSVRecord(transcription: $0) }
        )
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = VoiceInkTranscriptionCSVExporter.defaultFilename
        
        savePanel.begin { result in
            if result == .OK, let url = savePanel.url {
                do {
                    try csvString.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print(VoiceInkTranscriptionCSVExporter.writeFailureDiagnosticMessage(errorDescription: String(describing: error)))
                }
            }
        }
    }
}

private extension VoiceInkTranscriptionCSVRecord {
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
