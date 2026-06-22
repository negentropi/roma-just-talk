import SwiftUI
import UniformTypeIdentifiers
import VoiceInkCore

struct SaveIconButton: View {
    let textToSave: String
    @State private var saved = false

    var body: some View {
        Menu {
            Button(VoiceInkTranscriptPresentation.saveTranscriptAsPlainTextButtonTitle) {
                saveFile(
                    as: .plainText,
                    extension: VoiceInkTranscriptFileExport.plainTextFileExtension
                )
            }
            Button(VoiceInkTranscriptPresentation.saveTranscriptAsMarkdownButtonTitle) {
                saveFile(
                    as: .text,
                    extension: VoiceInkTranscriptFileExport.markdownFileExtension
                )
            }
        } label: {
            Image(
                systemName: saved
                    ? VoiceInkTranscriptPresentation.actionSucceededSystemImageName
                    : VoiceInkTranscriptPresentation.saveTranscriptSystemImageName
            )
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(saved ? .green : .secondary)
                .frame(width: 28, height: 28)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.9))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(VoiceInkTranscriptPresentation.saveTranscriptHelp)
    }

    private func saveFile(as contentType: UTType, extension fileExtension: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.nameFieldStringValue = "\(VoiceInkTranscriptFileExport.suggestedBaseFilename(for: textToSave)).\(fileExtension)"
        panel.title = VoiceInkTranscriptPresentation.saveTranscriptPanelTitle

        if panel.runModal() == .OK {
            guard let url = panel.url else { return }
            do {
                let content = fileExtension == VoiceInkTranscriptFileExport.markdownFileExtension
                    ? VoiceInkTranscriptFileExport.markdownContent(for: textToSave)
                    : textToSave
                try content.write(to: url, atomically: true, encoding: .utf8)
                withAnimation { saved = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation { saved = false }
                }
            } catch {
                print("\(VoiceInkTranscriptPresentation.saveTranscriptFailureConsolePrefix) \(error.localizedDescription)")
            }
        }
    }

}
