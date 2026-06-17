import FluidAudio
import Foundation
import VoiceInkCore

extension WordAgreementEngine {
    static func mergeTokensToWords(_ timings: [TokenTiming], timeOffset: Double = 0.0) -> [TimedWord] {
        guard !timings.isEmpty else { return [] }

        var words: [TimedWord] = []
        var currentText = ""
        var wordStart = 0.0
        var wordEnd = 0.0
        var currentConfidences: [Float] = []

        for timing in timings {
            let token = timing.token

            if token.hasPrefix("▁") || token.hasPrefix(" ") {
                if !currentText.isEmpty {
                    words.append(TimedWord(
                        text: currentText,
                        startTime: wordStart + timeOffset,
                        endTime: wordEnd + timeOffset,
                        confidence: averageConfidence(currentConfidences)
                    ))
                }
                let stripped = token.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "▁", with: "")
                currentText = stripped
                wordStart = timing.startTime
                wordEnd = timing.endTime
                currentConfidences = [timing.confidence]
            } else {
                if currentText.isEmpty {
                    wordStart = timing.startTime
                }
                currentText += token
                wordEnd = timing.endTime
                currentConfidences.append(timing.confidence)
            }
        }

        if !currentText.isEmpty {
            words.append(TimedWord(
                text: currentText,
                startTime: wordStart + timeOffset,
                endTime: wordEnd + timeOffset,
                confidence: averageConfidence(currentConfidences)
            ))
        }

        return words
    }

    private static func averageConfidence(_ confidences: [Float]) -> Float {
        confidences.isEmpty ? 1.0 : confidences.reduce(0, +) / Float(confidences.count)
    }
}
