import Foundation
import Testing
@testable import VoiceInk

private final class ModelChangeNotificationRecorder: NSObject {
    private(set) var modelChangeCount = 0
    private(set) var modelChangeUserInfos: [[AnyHashable: Any]?] = []
    private(set) var settingsChangeCount = 0

    @objc func modelDidChange(_ notification: Notification) {
        modelChangeCount += 1
        modelChangeUserInfos.append(notification.userInfo)
    }

    @objc func settingsDidChange(_ notification: Notification) {
        settingsChangeCount += 1
    }
}

@Suite(.serialized)
struct TranscriptionModelManagerTests {
    @Test @MainActor func loadingSavedCurrentModelBroadcastsModelAndSettingsChange() {
        let oldModelName = UserDefaults.standard.string(forKey: "CurrentTranscriptionModel")
        let oldLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage")
        defer {
            restoreDefault(oldModelName, forKey: "CurrentTranscriptionModel")
            restoreDefault(oldLanguage, forKey: "SelectedLanguage")
        }

        let recorder = ModelChangeNotificationRecorder()
        NotificationCenter.default.addObserver(
            recorder,
            selector: #selector(ModelChangeNotificationRecorder.modelDidChange(_:)),
            name: .didChangeModel,
            object: nil
        )
        NotificationCenter.default.addObserver(
            recorder,
            selector: #selector(ModelChangeNotificationRecorder.settingsDidChange(_:)),
            name: .AppSettingsDidChange,
            object: nil
        )
        defer { NotificationCenter.default.removeObserver(recorder) }

        UserDefaults.standard.set("ggml-tiny", forKey: "CurrentTranscriptionModel")
        UserDefaults.standard.set("auto", forKey: "SelectedLanguage")

        let whisperModelManager = WhisperModelManager(
            modelsDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let modelManager = TranscriptionModelManager(
            whisperModelManager: whisperModelManager,
            fluidAudioModelManager: FluidAudioModelManager()
        )

        modelManager.loadCurrentTranscriptionModel()

        #expect(modelManager.currentTranscriptionModel?.name == "ggml-tiny")
        #expect(recorder.modelChangeCount >= 1)
        #expect(recorder.modelChangeUserInfos.allSatisfy { $0?.isEmpty ?? true })
        #expect(recorder.settingsChangeCount >= 1)
    }

    private func restoreDefault(_ value: String?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
