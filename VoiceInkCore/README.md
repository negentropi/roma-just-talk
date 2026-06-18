# VoiceInkCore

Shared, platform-neutral VoiceInk code.

Module contract:
- Own shared business, transcription, prompt, provider, preference, file-policy, metrics, formatting, and presentation logic that must behave the same on macOS and iOS.
- Stay platform-neutral. Core sources and checks must not import AppKit, UIKit, SwiftUI, SwiftData, AVFoundation, CoreAudio, IOKit, FluidAudio, KeyboardKit, LLMkit, or whisper.cpp bindings.
- Leave platform shells responsible for UI, OS permissions, audio capture/playback, paste and keyboard behavior, keychain adapters, SwiftData storage, local model runtime/download orchestration, and provider-specific streaming adapters.

The macOS app remains behavior source-of-truth. iOS imports this package only for shared logic once a slice has replacement proof.

The detailed shared-module inventory and deletion gates live in `docs/ios-single-repo-migration.md`.

Verification:
- From the repo root, run `scripts/verify-ios-single-repo-migration.sh` for the shared-core plus macOS/iOS static gates.
- For only the package checks, run `swift run VoiceInkCoreChecks`.
- On the current Command Line Tools-only setup, `swift test` builds but cannot import XCTest or Swift Testing, so it does not execute the core checks.
