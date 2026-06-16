import Foundation
import VoiceInkCore

struct AIEnhancementOutputFilter {
    static func filter(_ text: String) -> String {
        VoiceInkAIEnhancementOutputFilter.filter(text)
    }
}
