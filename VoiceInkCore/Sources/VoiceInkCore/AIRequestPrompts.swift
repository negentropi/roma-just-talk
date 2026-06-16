public enum VoiceInkAIRequestPrompts {
    public static let postProcessingSystemPrompt = "You are a helpful assistant that rewrites raw speech-to-text transcripts to be concise, well-punctuated, and readable notes, preserving meaning."

    public static func taggedTranscript(_ text: String) -> String {
        "\n<TRANSCRIPT>\n\(text)\n</TRANSCRIPT>"
    }

    public static func postProcessingUserPrompt(prompt: String, transcript: String) -> String {
        "Prompt: \(prompt)\n\nTranscript:\n\(transcript)"
    }
}
