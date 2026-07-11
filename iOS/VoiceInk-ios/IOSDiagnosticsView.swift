import SwiftUI
import VoiceInkCore

struct IOSDiagnosticsView: View {
    @StateObject private var exporter = IOSDiagnosticExporter()
    @State private var range = VoiceInkIOSDiagnosticRange.oneHour

    var body: some View {
        Form {
            Section {
                Picker("Log Range", selection: $range) {
                    ForEach(VoiceInkIOSDiagnosticRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }

                Button {
                    exporter.prepare(range: range)
                } label: {
                    if exporter.isPreparing {
                        ProgressView()
                    } else {
                        Label("Prepare Support Bundle", systemImage: "doc.badge.gearshape")
                    }
                }
                .disabled(exporter.isPreparing)

                if let export = exporter.export {
                    ShareLink(item: export, preview: SharePreview(export.filename)) {
                        Label("Share Support Bundle", systemImage: "square.and.arrow.up")
                    }
                }
            } footer: {
                Text("Includes current-process app logs and basic device/configuration facts. Secrets, email addresses, and home-directory paths are redacted.")
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Export Failed",
            isPresented: Binding(
                get: { exporter.errorMessage != nil },
                set: { if !$0 { exporter.errorMessage = nil } }
            )
        ) {
            Button("OK") { exporter.errorMessage = nil }
        } message: {
            Text(exporter.errorMessage ?? "")
        }
    }
}
