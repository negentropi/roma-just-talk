import SwiftUI
import UniformTypeIdentifiers
import RomaCore

struct SaveIconButton: View {
    let textToSave: String
    @State private var saved = false

    var body: some View {
        Menu {
            Button(RomaTranscriptPresentation.saveTranscriptAsPlainTextButtonTitle) {
                saveFile(
                    as: .plainText,
                    extension: RomaTranscriptFileExport.plainTextFileExtension
                )
            }
            Button(RomaTranscriptPresentation.saveTranscriptAsMarkdownButtonTitle) {
                saveFile(
                    as: .text,
                    extension: RomaTranscriptFileExport.markdownFileExtension
                )
            }
        } label: {
            Image(
                systemName: saved
                    ? RomaTranscriptPresentation.actionSucceededSystemImageName
                    : RomaTranscriptPresentation.saveTranscriptSystemImageName
            )
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(saved ? .green : .secondary)
                .frame(width: 28, height: 28)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.9))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(RomaTranscriptPresentation.saveTranscriptHelp)
    }

    private func saveFile(as contentType: UTType, extension fileExtension: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.nameFieldStringValue = "\(RomaTranscriptFileExport.suggestedBaseFilename(for: textToSave)).\(fileExtension)"
        panel.title = RomaTranscriptPresentation.saveTranscriptPanelTitle

        if panel.runModal() == .OK {
            guard let url = panel.url else { return }
            do {
                let content = fileExtension == RomaTranscriptFileExport.markdownFileExtension
                    ? RomaTranscriptFileExport.markdownContent(for: textToSave)
                    : textToSave
                try content.write(to: url, atomically: true, encoding: .utf8)
                withAnimation { saved = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation { saved = false }
                }
            } catch {
                print("\(RomaTranscriptPresentation.saveTranscriptFailureConsolePrefix) \(error.localizedDescription)")
            }
        }
    }

}
