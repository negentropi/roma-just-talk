import XCTest
@testable import VoiceInkLip

final class CTCDecoderTests: XCTestCase {
    private var tokens: [String] {
        var tokens = [String](repeating: "", count: 1049)
        tokens[0] = "<blank>"
        tokens[1] = "▁hello"
        tokens[2] = "▁world"
        tokens[3] = "l"
        tokens[4] = "a"
        tokens[5] = "!"
        tokens[1048] = "<eos>"
        return tokens
    }

    private func decode(_ bestTokens: [Int]) throws -> String {
        var scores = [Float](repeating: -100, count: bestTokens.count * 1049)
        for (time, token) in bestTokens.enumerated() {
            scores[time * 1049 + token] = -0.01
        }
        return try CTCDecoder.decode(
            logProbabilities: scores,
            shape: [1, bestTokens.count, 1049],
            tokens: tokens
        )
    }

    func testSentencePieceWordsAndPunctuation() throws {
        XCTAssertEqual(try decode([0, 1, 1, 0, 2, 2, 5, 0]), "hello world!")
    }

    func testCollapseRepeatsBeforeRemovingBlank() throws {
        XCTAssertEqual(try decode([3, 3, 0, 3, 4]), "lla")
    }

    func testEOSAndBlankNeverAppearInText() throws {
        XCTAssertEqual(try decode([1048, 1048, 0, 1, 1048, 0, 2, 1048]), "hello world")
        XCTAssertEqual(try decode([0, 0, 1048, 1048, 0]), "")
    }

    func testSentencePieceSubwordsDoNotGainSpaces() throws {
        var vocabulary = tokens
        vocabulary[3] = "lo"
        vocabulary[1] = "▁hel"
        let scores: [Float] = [1, 3, 2].flatMap { best in
            (0..<1049).map { $0 == best ? Float(-0.01) : Float(-100) }
        }
        XCTAssertEqual(try CTCDecoder.decode(logProbabilities: scores, shape: [1, 3, 1049], tokens: vocabulary), "hello world")
    }

    func testMalformedShapeAndBufferAreRejected() {
        for shape in [[1, 1], [2, 1, 1049], [1, 0, 1049], [1, 1, 1048], [1, Int.max, 1049]] {
            XCTAssertThrowsError(try CTCDecoder.decode(logProbabilities: [], shape: shape, tokens: tokens))
        }
        XCTAssertThrowsError(try CTCDecoder.decode(logProbabilities: [0], shape: [1, 1, 1049], tokens: tokens))
        XCTAssertThrowsError(try CTCDecoder.decode(logProbabilities: [Float](repeating: 0, count: 1049), shape: [1, 1, 1049], tokens: []))
    }

    func testNonFiniteScoresAreRejectedEvenOutsideWinningToken() {
        for invalid in [Float.nan, Float.infinity, -Float.infinity] {
            var scores = [Float](repeating: -10, count: 1049)
            scores[1] = 0
            scores[1047] = invalid
            XCTAssertThrowsError(try CTCDecoder.decode(logProbabilities: scores, shape: [1, 1, 1049], tokens: tokens))
        }
    }

    func testInvalidInputRejectedBeforeOpeningModel() async {
        do {
            _ = try await CTCRecognizer().recognize(
                modelURL: URL(fileURLWithPath: "/missing-visual-ctc.onnx"),
                frames: [], frameCount: 1, tokens: tokens
            )
            XCTFail("A truncated mouth tensor must fail before model loading.")
        } catch let error as LipInferenceError {
            XCTAssertEqual(error, .invalidInput("Expected a mouth tensor with shape [1,T,88,88]."))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
