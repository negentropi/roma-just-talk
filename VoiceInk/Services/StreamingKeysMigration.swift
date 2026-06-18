import Foundation
import VoiceInkCore

// Safe to delete once all users have updated past this version.
enum StreamingKeysMigration {
    static func run() {
        VoiceInkStreamingKeysMigration.run()
    }
}
