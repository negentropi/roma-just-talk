import SwiftUI

struct DiagnosticsSettingsView: View {
    @State private var isExportingLogs = false
    @State private var exportedLogURL: URL?
    @State private var showLogExportError = false
    @State private var logExportError: String = ""
    @State private var rollingBufferClaim = RollingBufferPreloadRuntimeDiagnostics.shared.currentQuickReleaseClaim()

    var body: some View {
        Group {
            LabeledContent("Rolling Buffer Last Claim") {
                Text(rollingBufferClaim.displaySummary)
                    .foregroundStyle(.secondary)
            }

            LabeledContent {
                HStack(spacing: 8) {
                    if let url = exportedLogURL {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }

                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }

                    Button("Export") {
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
                    Text("Export Logs")
                }
            }
        }
        .onAppear(perform: refreshRollingBufferClaim)
        .alert("Export Failed", isPresented: $showLogExportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(logExportError)
        }
    }

    private func exportDiagnosticLogs() {
        refreshRollingBufferClaim()
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

    private func refreshRollingBufferClaim() {
        rollingBufferClaim = RollingBufferPreloadRuntimeDiagnostics.shared.currentQuickReleaseClaim()
    }
}
