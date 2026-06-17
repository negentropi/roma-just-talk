import Foundation

public struct TimedWord: Equatable, Sendable {
    public let text: String
    public let normalizedText: String
    public let startTime: Double
    public let endTime: Double
    public let confidence: Float

    public init(text: String, startTime: Double, endTime: Double, confidence: Float = 1.0) {
        self.text = text
        self.normalizedText = Self.normalize(text)
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }

    private static func normalize(_ text: String) -> String {
        String(text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .filter { $0.isLetter || $0.isNumber || $0.isWhitespace })
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct AgreementConfig: Equatable, Sendable {
    public var transcribeIntervalSeconds: Double
    public var tokenConfirmationsNeeded: Int
    public var minWordsToConfirm: Int
    public var minPassConfidence: Float
    public var minWordConfidence: Float
    public var cachedFinalizationMaxLagSeconds: Double
    public var runsImmediatePassOnBufferedAudio: Bool

    public init(
        transcribeIntervalSeconds: Double = 1.0,
        tokenConfirmationsNeeded: Int = 3,
        minWordsToConfirm: Int = 5,
        minPassConfidence: Float = 0.15,
        minWordConfidence: Float = 0.6,
        cachedFinalizationMaxLagSeconds: Double = 0.35,
        runsImmediatePassOnBufferedAudio: Bool = false
    ) {
        self.transcribeIntervalSeconds = transcribeIntervalSeconds
        self.tokenConfirmationsNeeded = tokenConfirmationsNeeded
        self.minWordsToConfirm = minWordsToConfirm
        self.minPassConfidence = minPassConfidence
        self.minWordConfidence = minWordConfidence
        self.cachedFinalizationMaxLagSeconds = cachedFinalizationMaxLagSeconds
        self.runsImmediatePassOnBufferedAudio = runsImmediatePassOnBufferedAudio
    }

    public static var rollingPreload: AgreementConfig {
        AgreementConfig(
            transcribeIntervalSeconds: 0.35,
            tokenConfirmationsNeeded: 3,
            minWordsToConfirm: 5,
            minPassConfidence: 0.15,
            minWordConfidence: 0.6,
            cachedFinalizationMaxLagSeconds: 0.25,
            runsImmediatePassOnBufferedAudio: true
        )
    }
}

public struct AgreementResult: Equatable, Sendable {
    public let fullText: String
    public let hypothesisText: String
    public let newlyConfirmedText: String
}

public final class WordAgreementEngine {

    private let config: AgreementConfig

    private var confirmedWords: [TimedWord] = []
    private var previousWords: [TimedWord] = []
    private var consecutiveAgreementCount: Int = 0
    private var isFirstPass: Bool = true

    public private(set) var confirmedEndTime: Double = 0.0
    public private(set) var hypothesisStartTime: Double = 0.0

    public var confirmedText: String {
        confirmedWords.map(\.text).joined(separator: " ")
    }

    public init(config: AgreementConfig = AgreementConfig()) {
        self.config = config
    }

    public func reset() {
        confirmedWords = []
        previousWords = []
        consecutiveAgreementCount = 0
        isFirstPass = true
        confirmedEndTime = 0.0
        hypothesisStartTime = 0.0
    }

    public func processTranscriptionResult(words: [TimedWord], resultConfidence: Float = 1.0) -> AgreementResult {
        guard !words.isEmpty else {
            return makeResult(hypothesisWords: [], newlyConfirmedWords: [])
        }

        if isFirstPass {
            isFirstPass = false
            previousWords = words
            return makeResult(hypothesisWords: words, newlyConfirmedWords: [])
        }

        if resultConfidence < config.minPassConfidence {
            consecutiveAgreementCount = 0
            previousWords = words
            return makeResult(hypothesisWords: words, newlyConfirmedWords: [])
        }

        let commonPrefix = findLongestCommonPrefix(current: words, previous: previousWords)
        previousWords = words

        if commonPrefix.count >= config.minWordsToConfirm {
            consecutiveAgreementCount += 1
        } else {
            consecutiveAgreementCount = 0
            return makeResult(hypothesisWords: words, newlyConfirmedWords: [])
        }

        guard consecutiveAgreementCount >= config.tokenConfirmationsNeeded else {
            return makeResult(hypothesisWords: words, newlyConfirmedWords: [])
        }

        let confirmUpTo = applyPunctuationRule(words: Array(words.prefix(commonPrefix.count)))

        guard confirmUpTo > 0 else {
            return makeResult(hypothesisWords: words, newlyConfirmedWords: [])
        }

        let boundaryWords = Array(words.prefix(confirmUpTo).suffix(3))
        let minBoundaryConfidence = boundaryWords.map(\.confidence).min() ?? 1.0
        guard minBoundaryConfidence >= config.minWordConfidence else {
            return makeResult(hypothesisWords: words, newlyConfirmedWords: [])
        }

        let newlyConfirmed = Array(words.prefix(confirmUpTo))
        let hypothesis = Array(words.dropFirst(confirmUpTo))

        confirmedWords.append(contentsOf: newlyConfirmed)
        if let lastConfirmed = newlyConfirmed.last {
            confirmedEndTime = lastConfirmed.endTime
        }

        hypothesisStartTime = hypothesis.first?.startTime ?? confirmedEndTime

        consecutiveAgreementCount = hypothesis.isEmpty ? 0 : 1
        previousWords = hypothesis
        isFirstPass = hypothesis.isEmpty

        return makeResult(hypothesisWords: hypothesis, newlyConfirmedWords: newlyConfirmed)
    }

    private func findLongestCommonPrefix(current: [TimedWord], previous: [TimedWord]) -> [TimedWord] {
        let minCount = min(current.count, previous.count)
        var prefixLength = 0

        for i in 0..<minCount {
            if current[i].normalizedText == previous[i].normalizedText {
                prefixLength = i + 1
            } else {
                break
            }
        }

        return Array(current.prefix(prefixLength))
    }

    private func applyPunctuationRule(words: [TimedWord]) -> Int {
        guard !words.isEmpty else { return 0 }

        let sentenceEnders: Set<Character> = [".", "!", "?", ";"]

        var punctuationIndices: [Int] = []
        for i in 0..<words.count {
            if let lastChar = words[i].text.last, sentenceEnders.contains(lastChar) {
                punctuationIndices.append(i)
            }
        }

        guard punctuationIndices.count >= 3 else { return 0 }

        let cutIndex = punctuationIndices[punctuationIndices.count - 3]
        let confirmCount = cutIndex + 1

        guard confirmCount >= config.minWordsToConfirm else { return 0 }

        return confirmCount
    }

    private func makeResult(hypothesisWords: [TimedWord], newlyConfirmedWords: [TimedWord]) -> AgreementResult {
        let confirmedText = confirmedWords.map(\.text).joined(separator: " ")
        let hypothesisText = hypothesisWords.map(\.text).joined(separator: " ")
        let newlyConfirmedText = newlyConfirmedWords.map(\.text).joined(separator: " ")

        var fullParts: [String] = []
        if !confirmedText.isEmpty { fullParts.append(confirmedText) }
        if !hypothesisText.isEmpty { fullParts.append(hypothesisText) }

        return AgreementResult(
            fullText: fullParts.joined(separator: " "),
            hypothesisText: hypothesisText,
            newlyConfirmedText: newlyConfirmedText
        )
    }
}
