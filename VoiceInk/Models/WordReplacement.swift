import Foundation
import SwiftData
import VoiceInkCore

@Model
final class WordReplacement {
    var id: UUID = UUID()
    var originalText: String = ""
    var replacementText: String = ""
    var dateAdded: Date = Date()
    var isEnabled: Bool = true

    init(originalText: String, replacementText: String, dateAdded: Date = Date(), isEnabled: Bool = true) {
        self.originalText = originalText
        self.replacementText = replacementText
        self.dateAdded = dateAdded
        self.isEnabled = isEnabled
    }

    var voiceInkRule: VoiceInkWordReplacementRule {
        VoiceInkWordReplacementRule(originalText: originalText, replacementText: replacementText)
    }
}
