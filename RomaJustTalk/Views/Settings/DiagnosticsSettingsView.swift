import SwiftUI
import RomaCore

struct DiagnosticsSettingsView: View {
    @State private var isExportingLogs = false
    @State private var exportedLogURL: URL?
    @State private var showLogExportError = false
    @State private var logExportError: String = ""

    var body: some View {
        Group {
            LabeledContent {
                HStack(spacing: 8) {
                    if let url = exportedLogURL {
                        Button(RomaDiagnosticsSettingsPresentation.showInFinderButtonTitle) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }

                        Image(systemName: RomaDiagnosticsSettingsPresentation.exportedLogSuccessSystemImageName)
                            .foregroundColor(.green)
                    }

                    Button(RomaDiagnosticsSettingsPresentation.exportButtonTitle) {
                        exportDiagnosticLogs()
                    }
                    .disabled(isExportingLogs)
                }
            } label: {
                HStack(spacing: 4) {
                    if isExportingLogs {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(RomaDiagnosticsSettingsPresentation.exportLogsLabel)
                }
            }
        }
        .alert(RomaDiagnosticsSettingsPresentation.exportFailedAlertTitle, isPresented: $showLogExportError) {
            Button(RomaDiagnosticsSettingsPresentation.alertDismissButtonTitle, role: .cancel) { }
        } message: {
            Text(logExportError)
        }
    }

    private func exportDiagnosticLogs() {
        isExportingLogs = true
        exportedLogURL = nil

        Task {
            do {
                let url = try await LogExporter.shared.exportLogs()
                await MainActor.run {
                    exportedLogURL = url
                    isExportingLogs = false
                }
            } catch {
                await MainActor.run {
                    logExportError = error.localizedDescription
                    showLogExportError = true
                    isExportingLogs = false
                }
            }
        }
    }
}
