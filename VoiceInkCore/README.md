# VoiceInkCore

Shared, platform-neutral VoiceInk code.

Initial boundary:
- Foundation-only prompt/template constants.
- No SwiftData models.
- No AppKit/UIKit shell code.
- No recorder, hotkey, paste, permission, or keyboard-extension code.

The macOS app remains behavior source-of-truth. iOS imports this package only for shared logic once a slice has replacement proof.

Verification:
- Run `swift run VoiceInkCoreChecks`.
- On the current Command Line Tools-only setup, `swift test` builds but cannot import XCTest or Swift Testing, so it does not execute the core checks.
