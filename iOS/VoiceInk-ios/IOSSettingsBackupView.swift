import SwiftUI
import UniformTypeIdentifiers
import VoiceInkCore

struct IOSSettingsBackupView: View {
    @StateObject private var manager = IOSSettingsBackupManager()
    @State private var exportCategories = Set(VoiceInkIOSSettingsBackupCategory.allCases)
    @State private var isFileImporterPresented = false

    var body: some View {
        Form {
            Section {
                categoryToggles(selection: $exportCategories)
                exportControl
            } header: {
                Text("Export")
            } footer: {
                Text("API keys, recordings, transcripts, and downloaded model files are never exported.")
            }

            Section {
                Button {
                    isFileImporterPresented = true
                } label: {
                    Label("Choose Backup", systemImage: "square.and.arrow.down")
                }

                if manager.pendingImport != nil {
                    categoryToggles(
                        selection: $manager.selectedImportCategories,
                        categories: manager.availableImportCategories
                    )

                    Button("Import Selected Settings") {
                        manager.applyPendingImport()
                    }
                    .disabled(manager.selectedImportCategories.isEmpty)

                    Button("Cancel Import", role: .cancel) {
                        manager.cancelImport()
                    }
                }
            } header: {
                Text("Import")
            } footer: {
                Text("Import replaces only the selected categories. Invalid files or storage failures leave the current settings unchanged.")
            }
        }
        .navigationTitle("Settings Backup")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            manager.loadImport(from: url)
        }
        .alert(
            "Settings Backup",
            isPresented: Binding(
                get: { manager.statusMessage != nil },
                set: { if !$0 { manager.statusMessage = nil } }
            )
        ) {
            Button("OK") { manager.statusMessage = nil }
        } message: {
            Text(manager.statusMessage ?? "")
        }
    }

    @ViewBuilder
    private var exportControl: some View {
        if !exportCategories.isEmpty,
           let exportItem = try? manager.exportItem(categories: exportCategories) {
            ShareLink(
                item: exportItem,
                preview: SharePreview(VoiceInkIOSSettingsBackupCodec.defaultFilename)
            ) {
                Label("Export Settings", systemImage: "square.and.arrow.up")
            }
        }
    }

    @ViewBuilder
    private func categoryToggles(
        selection: Binding<Set<VoiceInkIOSSettingsBackupCategory>>,
        categories: [VoiceInkIOSSettingsBackupCategory] = VoiceInkIOSSettingsBackupCategory.allCases
    ) -> some View {
        ForEach(categories, id: \.self) { category in
            Toggle(
                category.title,
                isOn: Binding(
                    get: { selection.wrappedValue.contains(category) },
                    set: { isSelected in
                        if isSelected {
                            selection.wrappedValue.insert(category)
                        } else {
                            selection.wrappedValue.remove(category)
                        }
                    }
                )
            )
        }
    }
}
