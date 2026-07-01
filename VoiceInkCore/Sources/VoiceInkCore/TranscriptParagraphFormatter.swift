import Foundation
import NaturalLanguage

public enum VoiceInkTranscriptParagraphFormatter {
    public static func format(_ text: String) -> String {
        let targetWordCount = 50
        let maxSignificantSentencesPerChunk = 4
        let minimumWordsForSignificantSentence = 4

        let detectedLanguage = NLLanguageRecognizer.dominantLanguage(for: text)
        let tokenizerLanguage = detectedLanguage ?? .english

        let allSentences = sentences(from: text, language: tokenizerLanguage)
        guard !allSentences.isEmpty else {
            return ""
        }

        var formattedChunks = [String]()
        var processedSentenceIndex = 0

        while processedSentenceIndex < allSentences.count {
            var tentativeSentences = [String]()
            var tentativeWordCount = 0
            var significantSentenceCount = 0

            for index in processedSentenceIndex..<allSentences.count {
                let sentence = allSentences[index]
                let wordsInSentence = VoiceInkWordCounter.count(in: sentence, language: tokenizerLanguage)

                tentativeSentences.append(sentence)
                tentativeWordCount += wordsInSentence

                if wordsInSentence >= minimumWordsForSignificantSentence {
                    significantSentenceCount += 1
                }

                if tentativeWordCount >= targetWordCount {
                    break
                }
            }

            let chunkSentences: [String]
            if significantSentenceCount > maxSignificantSentencesPerChunk {
                chunkSentences = firstSignificantSentences(
                    in: tentativeSentences,
                    limit: maxSignificantSentencesPerChunk,
                    minimumWordCount: minimumWordsForSignificantSentence,
                    language: tokenizerLanguage
                )
            } else {
                chunkSentences = tentativeSentences
            }

            guard !chunkSentences.isEmpty else {
                processedSentenceIndex += max(tentativeSentences.count, 1)
                continue
            }

            formattedChunks.append(chunkSentences.joined(separator: " "))
            processedSentenceIndex += chunkSentences.count
        }

        return formattedChunks
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sentences(from text: String, language: NLLanguage) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.setLanguage(language)

        var sentences = [String]()
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { sentenceRange, _ in
            let sentence = String(text[sentenceRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            sentences.append(sentence)
            return true
        }
        return sentences
    }

    private static func firstSignificantSentences(
        in sentences: [String],
        limit: Int,
        minimumWordCount: Int,
        language: NLLanguage
    ) -> [String] {
        var result = [String]()
        var significantCount = 0

        for sentence in sentences {
            result.append(sentence)

            if VoiceInkWordCounter.count(in: sentence, language: language) >= minimumWordCount {
                significantCount += 1
                if significantCount >= limit {
                    break
                }
            }
        }

        return result
    }
}
