import Foundation

public enum VoiceInkAppDataResetStep: Equatable, Sendable {
    case deleteTranscriptionRecords
    case cleanFiles(VoiceInkAppDataResetFilePlan)
    case resetAppSettings
}

public struct VoiceInkAppDataResetPlan: Equatable, Sendable {
    public let steps: [VoiceInkAppDataResetStep]

    public init(steps: [VoiceInkAppDataResetStep]) {
        self.steps = steps
    }

    public static func iOS(
        recordingsDirectory: URL,
        modelsDirectory: URL,
        cachesDirectory: URL,
        temporaryDirectory: URL
    ) -> Self {
        Self(steps: [
            .deleteTranscriptionRecords,
            .cleanFiles(VoiceInkAppDataResetFilePlan.iOS(
                recordingsDirectory: recordingsDirectory,
                modelsDirectory: modelsDirectory,
                cachesDirectory: cachesDirectory,
                temporaryDirectory: temporaryDirectory
            )),
            .resetAppSettings
        ])
    }
}

public struct VoiceInkAppDataResetFilePlan: Equatable, Sendable {
    public let directoriesToRemove: [URL]
    public let directoriesToEmpty: [URL]

    public init(
        directoriesToRemove: [URL] = [],
        directoriesToEmpty: [URL] = []
    ) {
        self.directoriesToRemove = directoriesToRemove
        self.directoriesToEmpty = directoriesToEmpty
    }

    public static func iOS(
        recordingsDirectory: URL,
        modelsDirectory: URL,
        cachesDirectory: URL,
        temporaryDirectory: URL
    ) -> Self {
        Self(
            directoriesToRemove: [
                recordingsDirectory,
                modelsDirectory
            ],
            directoriesToEmpty: [
                cachesDirectory,
                temporaryDirectory
            ]
        )
    }

    public func performBestEffort(fileManager: FileManager = .default) {
        for directory in directoriesToRemove where fileManager.fileExists(atPath: directory.path) {
            try? fileManager.removeItem(at: directory)
        }

        for directory in directoriesToEmpty {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else {
                continue
            }

            for url in contents {
                try? fileManager.removeItem(at: url)
            }
        }
    }
}
