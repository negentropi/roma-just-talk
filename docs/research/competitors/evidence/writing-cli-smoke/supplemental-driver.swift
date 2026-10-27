
private struct SupplementalCase: Decodable {
    let id: String
    let kind: VoiceInkWritingActionKind
    let transcript: String
    let selectedText: String
    let targetLanguage: String
}
@main struct SupplementalDriver {
    static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let data = try Data(contentsOf: folder.appendingPathComponent("additional-cases.json"))
        let cases = try JSONDecoder().decode([SupplementalCase].self, from: data)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for fixture in cases {
            let request = try VoiceInkWritingActionRequest(kind: fixture.kind, transcript: fixture.transcript, selectedText: fixture.selectedText, targetLanguage: fixture.targetLanguage)
            let payload = ["kind": request.kind.rawValue, "systemMessage": request.systemMessage, "userMessage": request.userMessage, "promptName": request.promptName]
            try encoder.encode(payload).write(to: folder.appendingPathComponent(fixture.id + ".request.json"))
            let prompt = VoiceInkLocalCLIPreference.fullPrompt(systemPrompt: request.systemMessage, userPrompt: request.userMessage)
            try prompt.write(to: folder.appendingPathComponent(fixture.id + ".full-prompt.txt"), atomically: true, encoding: .utf8)
        }
    }
}
