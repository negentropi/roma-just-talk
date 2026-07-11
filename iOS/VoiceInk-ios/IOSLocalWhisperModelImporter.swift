import Foundation
import VoiceInkCore

enum IOSLocalWhisperModelImportOutcome: Equatable, Sendable {
    case imported(VoiceInkWhisperLocalModelFile)
    case duplicate(filename: String)
    case unsupportedFile
    case failed(message: String)
}

enum IOSLocalWhisperModelImporter {
    static func importModel(
        from sourceURL: URL,
        into modelsDirectory: URL,
        fileManager: FileManager = .default
    ) -> IOSLocalWhisperModelImportOutcome {
        let accessedSecurityScopedResource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScopedResource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let plan = VoiceInkWhisperModelFiles.localModelImportPlan(
            from: sourceURL,
            in: modelsDirectory,
            fileManager: fileManager
        ) else {
            return .unsupportedFile
        }
        guard !plan.isDuplicate else {
            return .duplicate(filename: plan.modelFilename)
        }

        do {
            try fileManager.createDirectory(
                at: modelsDirectory,
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: sourceURL, to: plan.destinationURL)
            return .imported(plan.localModelFile)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }
}

struct IOSLocalWhisperModelImportAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String?

    static func success(filename: String) -> Self {
        Self(
            title: VoiceInkModelManagementPresentation.importedLocalModelSuccessTitle(
                filename: filename
            ),
            message: nil
        )
    }

    static func duplicate(filename: String) -> Self {
        Self(
            title: VoiceInkModelManagementPresentation.importedLocalModelAlreadyExistsTitle(
                modelFilename: filename
            ),
            message: nil
        )
    }

    static let unsupportedFile = Self(
        title: "Unsupported model file",
        message: VoiceInkModelManagementPresentation.importLocalModelHelpText
    )

    static func failure(message: String) -> Self {
        Self(
            title: VoiceInkModelManagementPresentation.importedLocalModelFailureTitle(
                errorDescription: message
            ),
            message: nil
        )
    }
}
