import Foundation

public enum VoiceInkWhisperTranscriptSegments {
    public static func joinedText(_ segments: [String]) -> String {
        segments.joined()
    }

    public static func joinedText(
        segmentCount: Int32,
        textAt index: (Int32) -> String?
    ) -> String {
        guard segmentCount > 0 else { return "" }

        var segments: [String] = []
        segments.reserveCapacity(Int(segmentCount))

        for segmentIndex in 0..<segmentCount {
            if let text = index(segmentIndex) {
                segments.append(text)
            }
        }

        return joinedText(segments)
    }
}
