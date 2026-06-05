# Windows Port Direction

Goal: make roma-just-talk work on Windows with the least duplicated code, while keeping the product thesis intact: speak before the hotkey, keep a short pre-roll mic buffer, then commit the captured thought to text.

This is not a SwiftUI-to-Windows port. Swift can run on Windows, but the current app shell is macOS-bound through SwiftUI, AppKit, SwiftData, AVFoundation, CoreAudio, Carbon, ApplicationServices, ScreenCaptureKit, Security, Sparkle, and other Apple frameworks. The low-redundancy path is a shared Swift core plus platform adapters.

## Decision

Build toward this shape:

```text
roma-just-talk
  RomaCore/
    recording state machine
    transcription model/provider interfaces
    cloud transcription providers
    whisper.cpp bridge interface
    text cleanup, insertion polish, dictionary logic
    settings and history protocols
  macOS app/
    existing SwiftUI/AppKit shell
    CoreAudio recorder adapter
    CGEvent/NSPasteboard paste adapter
    NSEvent/CGEventTap shortcut adapter
    SwiftData/Keychain/UserDefaults storage adapters
  Windows app/
    RomaWindowsAgent first, then tray or small desktop shell
    miniaudio/WASAPI recorder adapter
    Win32 hotkey/hook adapter
    Win32 clipboard + SendInput paste adapter
    DPAPI/plain-settings storage adapter
```

The first Windows target should be an agent/proof executable, not a full re-created UI. It only needs to prove:

1. Start a rolling pre-roll mic buffer.
2. Press a global shortcut.
3. Include audio from before the shortcut in the WAV/PCM stream.
4. Transcribe through cloud STT or whisper.cpp.
5. Paste into Notepad or another normal-integrity app.

After that works, add tray/settings/history UI.

## Existing Seams

Reusable now:

- `TranscriptionService` already abstracts file-based STT.
- Cloud provider code is mostly HTTP + model metadata.
- `TranscriptionOutputFilter`, formatter, prompt detection, word replacements, and dictionary behavior are product logic.
- `PCMPreRollBuffer` now lives in `RomaCore` as Foundation-only circular PCM storage.
- `PCM16WAVFile` now lives in `RomaCore` as Foundation-only PCM16 WAV output for proof recordings.
- `MiniaudioCaptureRecorder` now lives in `RomaCore` and feeds miniaudio capture frames into the shared pre-roll/WAV path.
- `OpenAICompatibleTranscriptionService` now lives in `RomaCore` as a Foundation-only multipart HTTP proof path for OpenAI-compatible cloud STT.
- `WhisperCLITranscriptionService` now lives in `RomaCore` as a Foundation-only bridge to the proven `whisper-cli` executable and ggml model files.
- `DictationPipeline` now lives in `RomaCore` as the shared record -> transcribe -> shared cleanup -> optional paste orchestration. Its default lifecycle stops capture after one shot, while listener mode can keep capture alive so pre-roll keeps filling during transcription and paste finalization.
- `RomaTranscriptionOutputFilter` now lives in `RomaCore` as the shared Foundation-only post-STT cleanup and insertion-polish path.
- `RomaWordReplacementProcessor` now lives in `RomaCore` as the shared dictionary replacement matching path.
- `ClipboardRestoreConfiguration` now lives in `RomaCore` as the shared default for restoring clipboard text after paste; the Windows-specific name remains an alias for compatibility with the Windows adapter/proof surface.
- `RomaTranscriptionClient` now lives in `RomaCore` so proof tooling, `RomaWindowsAgent`, and future Windows UI code share the same OpenAI-compatible vs local `whisper-cli` selection.
- `WindowsDictationRuntime` now lives in `RomaCore` as the reusable Windows hotkey/hook -> miniaudio -> shared `DictationPipeline` -> optional Win32 paste composition.
- `RomaWindowsAgent` is the first user-facing Windows executable. It stays thin and calls `WindowsDictationRuntime` instead of duplicating recorder/STT/paste orchestration. Its `dictate` mode runs one proofable session; its `listen` mode uses a shared pre-roll runtime so capture stays alive between repeated hotkey sessions.
- `windows-proof-common.ps1` owns the packaged proof-surface file list, installed proof-report file map, script option compatibility checks, plus config-argument and wrapper-option helpers so source proof, installed launcher, artifact proof, laptop proof, and smoke proof use the same files and hold/paste/clipboard/replacement grammar.
- `RomaWindowsAgentConfiguration` now lives in `RomaCore` as the reusable JSON settings shape for endpoint, model, key source, trigger mode, paste, clipboard restore, language/prompt, and replacement defaults.
- `WindowsHotKey.proofToggle` and the Windows-only `WindowsRegisterHotKeyProof` source define the first `RegisterHotKey` toggle proof path. `windows-hotkey-availability-proof` performs a noninteractive register/unregister check before the interactive keypress proof.
- `WindowsLowLevelKeyboardHookProof` now defines the first `WH_KEYBOARD_LL` hold-to-talk keydown/keyup proof path.
- The user-facing hold-to-talk runtime keeps one low-level hook alive from keydown through keyup, so recording starts after the same hook observes keydown and stops when that hook observes release.
- The packaged proof-agent doctor prints `windows_hold_hook_single_window_source=true`, `windows_listener_output_isolation_source=true`, and `windows_listener_pre_roll_runtime_source=true`, and proof reports/checkers require them before accepting Windows artifact proof.
- `WindowsClipboardPayload` and the Windows-only `WindowsPasteProof` source define the first `CF_UNICODETEXT` plus `SendInput` paste proof path.
- `WindowsPermissionSurface` now lives in `RomaCore` as the shared permission/native-limit descriptor for laptop proof output.
- `WindowsDPAPISecretStore` now lives in `RomaCore` as the first Windows API-key storage adapter.
- `CoreAudioRecorder` already outputs the right streaming shape: 16 kHz mono Int16 PCM chunks and a WAV file with a 3 second pre-roll buffer, and now reuses `RomaCore.PCMPreRollBuffer`.

Not reusable without adapters:

- `VoiceInkEngine` owns SwiftData, AppKit notifications, macOS permission prompts, recorder UI, storage, and paste side effects.
- `TranscriptionPipeline` calls SwiftData directly and pastes through `CursorPaster`.
- `ShortcutMonitor` is macOS-only: `NSEvent`, `CGEventTap`, `AXIsProcessTrusted`, `CGPreflightListenEventAccess`.
- `CursorPaster` is macOS-only: `NSPasteboard`, AppleScript, `CGEvent`, Accessibility.
- `CoreAudioRecorder` is macOS-only: CoreAudio AudioUnit and ExtAudioFile.
- `KeychainService` is macOS-only outside local builds: Security framework.

## Adapter Interfaces To Extract First

Keep these narrow. Each Windows implementation should satisfy the same behavior the macOS app already expects.

```swift
protocol RollingRecorder {
    var onAudioChunk: (@Sendable (Data) -> Void)? { get set }
    func startPreRollBuffering() async throws
    func startRecording(toOutputFile url: URL) async throws
    func finishRecording() async throws
    func stopCapture() async
}

protocol ShortcutListening {
    func start(onKeyDown: @escaping () -> Void, onKeyUp: @escaping () -> Void) throws
    func stop()
}

protocol TextInsertion {
    func pasteAtCursor(_ text: String) async throws
}

protocol PermissionStatusProviding {
    func microphoneStatus() -> PermissionStatus
    func shortcutStatus() -> PermissionStatus
    func pasteStatus() -> PermissionStatus
}

protocol SecretStoring {
    func save(_ value: String, forKey key: String) throws
    func get(_ key: String) throws -> String?
    func delete(_ key: String) throws
}
```

The first refactor should not move every file. Start by making `TranscriptionPipeline` return a result instead of directly saving and pasting, then wrap platform actions outside core.

## Proven Windows Pieces

These are the lowest-redo candidates because they map directly to the behavior already in the macOS app.

| Need | Windows path | Why |
| --- | --- | --- |
| Rolling mic capture | miniaudio first, raw WASAPI second | miniaudio is single-file C, supports capture, WASAPI, Core Audio, conversion, and ring buffers. `RomaProofAgent miniaudio-record-proof` is the first source path for this. |
| Local Whisper | whisper.cpp CLI first, C API/DLL second | Current app already uses whisper.cpp; upstream supports Windows with MSVC/MinGW and CPU/GPU paths. `WhisperCLITranscriptionService` keeps this as an external executable seam before linking the C++ engine into Swift. |
| Cloud STT | Existing OpenAI-compatible provider logic behind a portable API-key source | Low native surface; fastest proof if local model packaging is not ready. `RomaProofAgent transcribe-proof` is the first source path for this. |
| Global shortcut | `RegisterHotKey` for toggle proof | Simple system-wide hotkey, enough for MVP toggle mode. `RomaProofAgent windows-hotkey-availability-proof` proves the default chord can be claimed; `windows-hotkey-proof` then proves actual delivery. |
| Push-to-talk keydown/keyup | `WH_KEYBOARD_LL` after toggle proof | Needed for hold behavior. `RomaProofAgent windows-keyboard-hook-proof` is the first source path for this and still keeps the hook work in a native adapter. |
| Paste | Win32 clipboard plus `SendInput` Ctrl+V | Same MVP behavior as macOS paste: put text on the clipboard, synthesize the paste command, then restore the previous text clipboard after a delay if the clipboard still contains the dictated text. `RomaProofAgent windows-paste-proof` is the first source path for this. |
| Secrets | DPAPI | Windows user-bound secret storage equivalent for API keys. `RomaProofAgent windows-secret-proof` is the first source path for this. |
| UI | tray/small shell first; Tauri optional later | Avoid re-creating all SwiftUI views before the actual Windows native behavior is proven. |

## Permission Model

Windows is not macOS TCC.

- Microphone: users need global microphone access and desktop-app microphone access enabled. Individual toggles are mainly Store/MSIX/package-identity flows.
- Global hotkey: `RegisterHotKey` generally has no permission prompt, but it can conflict with existing hotkeys.
- Low-level hooks: `WH_KEYBOARD_LL` can work for desktop apps, but requires a message loop and careful cleanup. Use only when hold-to-talk is required.
- Paste/input injection: `SendInput` can be blocked by integrity boundaries. A normal app should not expect to paste into elevated/admin apps.
- Clipboard restore: the Windows MVP restores the previous text clipboard only. It does not yet preserve every non-text clipboard format.
- Screen/window context: skip for MVP. Screen OCR/context has a separate permission and product-risk surface on both platforms.

Minimum Windows MVP surface: microphone + shortcut + clipboard/paste. The only OS permission grant in that MVP is microphone access; hotkey, paste, DPAPI, and login start are native capabilities with no prompt flow, and the Windows doctor explicitly reports no Accessibility, Automation, Screen Recording, or screen-capture requirement. Paste is still limited to equal-or-lower integrity targets. Do not start with screen capture, browser URL detection, media control, or app-aware modes.
Run `swift run RomaProofAgent windows-permission-doctor` or `RomaWindowsAgent doctor` to print the shared OS-grant/native-capability split before laptop smoke tests. The doctor also prints `microphone_settings_uri=ms-settings:privacy-microphone`, which is the direct Windows Settings page to open when laptop microphone access blocks preflight. `run-windows-laptop-proof.ps1` runs the packaged `RomaProofAgent.exe windows-permission-doctor` as its first laptop preflight and archives those booleans in the preflight JSON before hotkey or microphone capture proof.

## First Implementation Plan

1. Add `RomaCore` as a SwiftPM package or internal package folder. The initial package now exists under `RomaCore/` with portable interfaces for recorder, shortcut, paste, permissions, secrets, settings, and transcription services, plus shared pre-roll PCM buffering, PCM16 WAV output, miniaudio capture, Windows hotkey/paste proof metadata, and a portable `RomaProofAgent` executable.
2. Move only pure types and services first:
   - `TranscriptionService`
   - model/provider types that do not import SwiftData/AppKit
   - cloud provider request builders
   - text cleanup and insertion polish
   - result structs for `TranscriptionPipeline`
3. Replace direct platform calls with injected protocols:
   - storage instead of SwiftData in core
   - settings instead of `UserDefaults`
   - paste instead of `CursorPaster`
   - notifications instead of `NotificationManager`
4. Route command-line proof flows through `DictationPipeline` before building UI. This keeps Windows from growing a second orchestration path.
5. Add macOS adapters that call the current implementations. This proves extraction without behavior change.
6. Add a Windows proof target:
   - miniaudio recorder shim emits 16 kHz mono Int16 PCM and WAV
   - `RegisterHotKey` toggles start/stop
   - cloud STT first, or whisper.cpp CLI/DLL if model packaging is ready
   - Win32 clipboard + `SendInput` pastes text
   - `windows-dictation-proof` composes those pieces into one hotkey -> pre-roll WAV -> STT -> optional paste proof through the same cloud/local transcription config path as `RomaWindowsAgent`
7. Use `RomaWindowsAgent` as the first laptop-usable Windows entrypoint, then add tray/settings UI around the same runtime.

## Windows Proof Checklist

Run on a Windows laptop or Windows CI runner with audio loopback/mock where possible:

```powershell
cd RomaCore
powershell -ExecutionPolicy Bypass -File .\Scripts\windows-proof.ps1
powershell -ExecutionPolicy Bypass -File .\Scripts\package-windows-agent.ps1 -OutputDir C:\tmp\roma-windows-agent
powershell -ExecutionPolicy Bypass -File C:\tmp\roma-windows-agent\smoke-windows-agent.ps1 -PackageDir C:\tmp\roma-windows-agent
powershell -ExecutionPolicy Bypass -File C:\tmp\roma-windows-agent\install-windows-agent.ps1 -PackageDir C:\tmp\roma-windows-agent
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\roma-just-talk\agent\run-windows-agent.ps1" -DoctorOnly
```

For the foreground-dependent proofs:

```powershell
powershell -ExecutionPolicy Bypass -File .\Scripts\windows-proof.ps1 -RunInteractiveHotkey
powershell -ExecutionPolicy Bypass -File .\Scripts\windows-proof.ps1 -RunInteractivePaste
powershell -ExecutionPolicy Bypass -File .\Scripts\windows-proof.ps1 -RunNotepadPasteProof
```

Targeted paste activation restores the target window, temporarily bridges the current thread to the foreground and target input queues with `AttachThreadInput`, then calls `SetForegroundWindow` before `SendInput`. This improves normal Notepad/editor proof reliability but does not remove the equal-or-lower integrity limit.

Useful script options:

- `-SkipMic` skips real microphone capture when Windows microphone access is not ready.
- `-RecordSeconds 5` changes the live mic capture window.
- `-OutputDir C:\tmp\roma-proof` writes proof WAVs somewhere explicit.
- `-TranscribeEndpoint https://api.groq.com/openai/v1/audio/transcriptions -TranscribeModel whisper-large-v3-turbo -TranscribeApiKeyEnv GROQ_API_KEY` runs the OpenAI-compatible transcription proof.
- `-TranscribeApiKeyName groq` stores `-TranscribeApiKeyEnv` into DPAPI and uses the stored key for transcription.
- `-WhisperCLI C:\path\whisper-cli.exe -WhisperModel C:\path\ggml-base.en.bin` writes the user-facing Windows agent config for local whisper.cpp transcription.
- `-TranscribeAudio C:\tmp\proof.wav` uses an existing WAV for transcription, useful with `-SkipMic`.
- `-TranscribeLanguage en` and `-TranscribePrompt "roma just talk"` pass optional STT hints.
- `-WordReplacement "just talk=roma-just-talk"` adds a proof-time dictionary replacement before optional paste.
- `-CloudExpectedTranscriptText "cloud pre roll proof"` and `-LocalWhisperExpectedTranscriptText "local whisper pre roll proof"` change the laptop proof phrases that must appear in dictation transcripts.
- `-RunInteractiveDictation` waits for `Ctrl+Shift+R`, records with pre-roll, transcribes, and writes `dictation-proof.wav`.
- `-RunInteractiveWindowsAgent` writes `windows-agent.json`, then runs the user-facing `RomaWindowsAgent dictate --config windows-agent.json` command and writes `windows-agent-dictation.wav`.
- `-UseHoldHook` makes interactive dictation use `WH_KEYBOARD_LL`: recording starts on `Ctrl+Shift+R` keydown and stops on keyup.
- `-HoldTimeoutSeconds 15` changes the keydown/keyup wait timeout for hold-hook dictation.
- `-PasteFocusDelaySeconds 5` gives you time to focus Notepad or another normal-integrity text field before the standalone paste proof sends `Ctrl+V`.
- `-RunNotepadPasteProof` opens a real Notepad file, targets its process id through the Swift paste proof, saves the file, and verifies the pasted text on disk.
- `-PasteDictation` adds the final paste step to the interactive dictation proof.

Packaged artifact smoke test:

```powershell
powershell -ExecutionPolicy Bypass -File C:\tmp\roma-windows-agent\smoke-windows-agent.ps1 -PackageDir C:\tmp\roma-windows-agent
powershell -ExecutionPolicy Bypass -File C:\tmp\roma-windows-agent\prove-windows-agent-artifact.ps1 -PackageDir C:\tmp\roma-windows-agent -DoctorOnly -ProofReportPath C:\tmp\roma-windows-agent-doctor-proof.json
powershell -ExecutionPolicy Bypass -File C:\tmp\roma-windows-agent\check-windows-proof-report.ps1 -ProofReportPath C:\tmp\roma-windows-agent-doctor-proof.json -RequireProofProfile doctor-only
powershell -ExecutionPolicy Bypass -File C:\tmp\roma-windows-agent\smoke-windows-agent.ps1 -PackageDir C:\tmp\roma-windows-agent -Endpoint https://api.groq.com/openai/v1/audio/transcriptions -Model whisper-large-v3-turbo -ApiKeyEnv GROQ_API_KEY -RunDictation -PasteDictation
powershell -ExecutionPolicy Bypass -File C:\tmp\roma-windows-agent\smoke-windows-agent.ps1 -PackageDir C:\tmp\roma-windows-agent -Endpoint https://api.groq.com/openai/v1/audio/transcriptions -Model whisper-large-v3-turbo -ApiKeyEnv GROQ_API_KEY -ApiKeyName groq -RunDictation -PasteDictation
```

The first command proves the packaged `RomaWindowsAgent.exe doctor` and `write-config` path without SwiftPM. The second and third commands validate the packaged artifact, manifest, required scripts, Swift runtime DLL, permission surface, packaged `RomaProofAgent.exe` source surface, and packaged native doctors before any laptop install. The fourth command is the installed smoke proof: it prints shared `ACTION_REQUIRED` operator markers, then holds or toggles `Ctrl+Shift+R`, records, transcribes, and optionally pastes through the same config path. The fifth command first saves `GROQ_API_KEY` into the packaged agent's DPAPI secret store as `groq`, then writes config using the stored key name.

`package-windows-agent.ps1` must run on Windows. It refuses non-Windows hosts so a macOS/Linux Swift executable cannot be copied into a file named `RomaWindowsAgent.exe` and mistaken for laptop proof. It copies Swift runtime DLLs from the PATH directory containing `swiftCore.dll` into the artifact. On Windows, packaging fails if no runtime DLLs are copied or if `swiftCore.dll` is missing from the artifact; that keeps CI from passing only because the runner has Swift on `PATH`. The artifact also includes `WINDOWS-LAPTOP-PROOF.txt`, a self-contained preflight/full-proof command guide for the target laptop.

No-admin install proof:

```powershell
powershell -ExecutionPolicy Bypass -File C:\tmp\roma-windows-agent\install-windows-agent.ps1 -PackageDir C:\tmp\roma-windows-agent
powershell -ExecutionPolicy Bypass -File C:\tmp\roma-windows-agent\install-windows-agent.ps1 -PackageDir C:\tmp\roma-windows-agent -WhisperCLI C:\path\whisper-cli.exe -WhisperModel C:\path\ggml-base.en.bin
powershell -ExecutionPolicy Bypass -File C:\tmp\roma-windows-agent\install-windows-agent.ps1 -PackageDir C:\tmp\roma-windows-agent -Endpoint https://api.groq.com/openai/v1/audio/transcriptions -Model whisper-large-v3-turbo -ApiKeyEnv GROQ_API_KEY -ApiKeyName groq -RunDictation -PasteDictation
```

By default this installs into `%LOCALAPPDATA%\roma-just-talk\agent` and smokes the installed copy with an install-local smoke config. Passing `-WhisperCLI` and `-WhisperModel` proves the same installed config path for local whisper.cpp without API-key storage. When you pass real endpoint/model/key options or `-RunDictation`, the installer stores config at `%APPDATA%\roma-just-talk\windows-agent.json`. Pass `-InstallDir` and `-ConfigPath` to prove a temp install path in CI.
Before copying package files, the installer checks whether the existing installed `RomaWindowsAgent.exe` is still running and fails with its pid/path when found. Close the listener before reinstalling or upgrading; the installer does not stop it for you.
The installer copies the packaged proof surface too: `RomaProofAgent.exe`, `prove-windows-agent-artifact.ps1`, `run-windows-laptop-proof.ps1`, `WINDOWS-LAPTOP-PROOF.txt`, `check-windows-scripts-parse.ps1`, `windows-proof-common.ps1`, `windows-manifest.ps1`, `windows-package-identity.ps1`, and both proof checkers. The artifact proof report records those installed copies and the checker hash-matches them against the package, keeping an installed proof directory usable as a complete artifact surface instead of only a runtime launcher.

The installer also copies `run-windows-agent.ps1`. Use it to start one installed dictation session from the saved config, pass `-Listen` to keep the agent alive for repeated hotkey sessions, or pass endpoint/model/key options once to write config and immediately run dictation:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\roma-just-talk\agent\run-windows-agent.ps1"
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\roma-just-talk\agent\run-windows-agent.ps1" -Listen
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\roma-just-talk\agent\run-windows-agent.ps1" -Endpoint https://api.groq.com/openai/v1/audio/transcriptions -Model whisper-large-v3-turbo -ApiKeyEnv GROQ_API_KEY -ApiKeyName groq -PasteDictation
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\roma-just-talk\agent\run-windows-agent.ps1" -WhisperCLI C:\path\whisper-cli.exe -WhisperModel C:\path\ggml-base.en.bin -PasteDictation
```

Listener mode generates a fresh temp WAV path for each completed session even when the saved config contains an `outputPath`; pass `--out` directly to `RomaWindowsAgent listen` only when you intentionally want a fixed proof file.

Artifact-to-laptop proof wrapper:

```powershell
powershell -ExecutionPolicy Bypass -File C:\tmp\roma-windows-agent\run-windows-laptop-proof.ps1 -PackageDir C:\tmp\roma-windows-agent -ProofDir C:\tmp\roma-windows-laptop-proof -Endpoint https://api.groq.com/openai/v1/audio/transcriptions -Model whisper-large-v3-turbo -ApiKeyEnv GROQ_API_KEY -ApiKeyName groq -WhisperCLI C:\path\whisper-cli.exe -WhisperModel C:\path\ggml-base.en.bin
```

The laptop proof runner calls the artifact wrapper three times: cloud dictation with hold-to-talk and paste, local whisper dictation plus one installed listener session with hold-to-talk and paste, and local whisper Notepad paste. It stamps the preflight report plus all three interactive reports with one `proof_session_id`, gives cloud and local whisper separate proof-owned startup shortcut directories, then calls `check-windows-proof-set.ps1 -RequireFullLaptopProof` over the four JSON reports. This is the preferred laptop handoff command because it reuses the proven scripts instead of adding another install, dictation, listener, or paste path. Pass `-StartupShortcutDir C:\tmp\roma-startup-proof` only when you want those proof shortcut directories under a specific non-login location.
The laptop runner resolves the packaged artifact wrapper, proof-set checker, proof agent, and proof helper through `manifest.txt` with `Require-RomaWindowsManifestFile`; if the artifact was downloaded or moved after packaging, rooted manifest paths fall back through the current artifact directory plus the original subdirectory and filename, then only use filename-only relocation when it is unambiguous. The archived full-proof recheck script resolves the proof-set checker the same way before validating the saved reports.
Pass `-PreflightOnly -NativePreflightOnly` to run just the packaged hotkey-delivery and microphone checks before providing cloud credentials or local whisper paths. Pass `-PreflightOnly` with `-WhisperCLI` and `-WhisperModel` to include the local-whisper setup check too. Both modes write `preflight-proof.json` under `-ProofDir` by default, archive the hotkey key-down/key-up plus 16 kHz mono, positive-duration, and positive-pre-roll microphone output markers, validate through `check-windows-proof-report.ps1 -RequireProofProfile laptop-preflight` inside the set checker, require packaged source provenance with `source_dirty=false`, and print `proof_profile_ok=laptop-preflight` plus `proof_set_ok=laptop-preflight`; the local-whisper mode also archives no-network whisper output markers. Pass `-PreflightReportPath` when you want that JSON proof in a specific handoff location. Full laptop proof writes the same preflight report before interactive dictation, requires local-whisper preflight evidence, and includes it in the final set check.
The generated `WINDOWS-LAPTOP-PROOF.txt` separates operator actions, full-proof prerequisites, preflight-only markers, full-proof markers, archived preflight/full-proof recheck commands, and final claim gate. The operator action block, prerequisite block, preflight-only marker block, local-whisper preflight add-on marker, full-proof marker block, archived recheck assertions, default report filenames, and claim gate come from the shared proof helper so the guide and recheck script cannot drift on the expected profile markers, manual hotkey/transcript steps, microphone Settings URI, real cloud/local whisper prerequisites, clean-source requirement, report path contract, or `proof_set_ok=full-laptop` / `windows_laptop_recheck_ok=true` closeout. The laptop runner also prints hotkey-delivery, dictation, and Notepad-paste operator prompts through that helper instead of script-local prompt functions. The preflight recheck calls `check-windows-proof-report.ps1 -RequireProofProfile laptop-preflight` against the single preflight JSON; the full-proof recheck calls `check-windows-proof-set.ps1` over the four JSON reports without rerunning capture, transcription, listener, or paste. After the full laptop proof passes, the runner also writes `recheck-full-laptop-proof.ps1` into `-ProofDir` with the exact report paths from that run; the recheck script resolves the proof helper from the manifest and asserts the four profile markers plus `proof_set_ok=full-laptop` before printing `windows_laptop_recheck_ok=true`. `proof_set_laptop_preflight_matches_full=true` appears only after the full proof set check ties preflight, cloud dictation, local whisper dictation, and Notepad paste reports together.
Before mic and STT preflights, the laptop proof runner prints `ACTION_REQUIRED=hotkey_delivery_preflight` and runs the packaged `RomaProofAgent.exe windows-keyboard-hook-proof` command. Press and release `Ctrl+Shift+R` once; the preflight fails early unless the native hold-hook path reports both `key_down=true` and `key_up=true`.
Before the interactive runs, the laptop proof runner records `mic-preflight.wav` with the packaged `RomaProofAgent.exe miniaudio-record-proof` command and asserts the 16 kHz mono WAV has payload bytes plus positive `duration_seconds` and `included_pre_roll_seconds`. Pass `-MicPreflightSeconds 2` when you want a longer microphone-access check before the full laptop proof.
Before the interactive runs, the laptop proof runner uses the packaged `RomaProofAgent.exe whisper-cli-doctor` command to preflight the real `whisper-cli.exe`, model path, optional output directory, and extra whisper arguments. This catches missing or malformed local-whisper setup before the operator starts the long cloud/local/Notepad proof sequence.
Before each interactive dictation proof, the runner prints `ACTION_REQUIRED`, `say_expected_phrase_before_hotkey`, `hold_hotkey=Ctrl+Shift+R`, and the hold timeout so the operator can focus a normal text target and capture pre-roll speech deliberately. The default expected phrases are `cloud pre roll proof` and `local whisper pre roll proof`; pass `-CloudExpectedTranscriptText` or `-LocalWhisperExpectedTranscriptText` to change them. The report checker matches the expected phrase against the `processed_transcript_text` runtime field, not arbitrary log output.
The runner must be executed on Windows and requires real local `whisper-cli.exe` plus `.bin` or `.gguf` whisper model file paths; the packaged mock backend remains CI-only.
Installed proof reports now preserve the `config-doctor` result so archived laptop/CI proof shows the config path, transcription backend, cloud key source, and local whisper file checks before capture starts.
The wrapper validates the packaged artifact and manifest through shared packaged helpers, runs the packaged agent and proof-agent doctors, delegates install/config/shortcut work to `install-windows-agent.ps1`, then verifies the installed launcher with `-DoctorOnly`. That installed launcher doctor now asserts the same microphone-only OS grant, no-admin native hotkey/paste/DPAPI, and startup listener contract before starting dictation or listener mode. Normal installed runs call `RomaWindowsAgent config-doctor --config ...` before waiting for the hotkey, so missing API-key sources or local whisper files fail before capture starts.
Pass `-ProofReportPath` to leave a JSON proof record with package/install paths, source repository/branch/commit/dirty provenance, Windows version/user identity, package identity fingerprint, config output path, dictation/paste flags, non-secret transcription config fields, doctor permission-surface output, user-facing agent runtime wiring for `WindowsDictationRuntime`, miniaudio, Win32 paste, and DPAPI, proof-agent native-adapter runtime and source-surface output including the Windows runtime's shared `DictationPipeline` use, packaged native doctor output for hotkey, hold-hook, paste, DPAPI, and miniaudio capture, packaged and installed listener smoke output, file existence/byte counts/hash fields for the agent, packaged proof agent, installed launcher, optional shortcuts, exact shortcut target/argument/config references, local whisper files, dictation WAV, runtime-written WAV path, duration, sample rate, channel count, numeric pre-roll fields, non-empty raw and processed transcript lengths, expected transcript phrase match, ordered hold-to-talk runtime markers, Notepad paste-file proof when `-RunNotepadPasteProof` runs, and the `RomaWindowsAgent dictate` runtime log when `-RunDictation` creates one. Run `check-windows-proof-report.ps1` afterward to fail fast if the expected mode, source provenance, Windows platform/user, package identity, packaged and installed listener mode, installed listener config and agent paths, installed agent/launcher hash match, exact shortcut launcher/config arguments, cloud/local-whisper config, permission surface, user-facing agent runtime wiring, proof-agent native adapter runtime and source surface, native doctor surface, hold-hook config and ordered runtime keydown/key-up sequence, install, shortcut/startup shortcut launch target, dictation WAV, 16 kHz mono audio contract, positive duration and pre-roll, positive transcript lengths, expected transcript phrase, Notepad file paste, or paste proof fields are missing.
Use `-RequireProofProfile` for the normal proof modes so the checker expands a single profile into the required atomic assertions and prints `proof_requirement=... status=pass` coverage lines, including `agent_runtime_wiring` for the user-facing `WindowsDictationRuntime`/miniaudio/Win32 paste/DPAPI doctor markers, `shared_windows_transcription_path` and `shared_windows_proof_args` for the low-redundancy cloud/local config path, `listener_pre_roll_runtime_source` for listener mode staying on the pre-roll dictation runtime path, `listener_shared_pre_roll_runtime` for the installed listener's shared capture lifecycle marker, `hold_hook_single_window_source` for the single native hold-hook window source marker, and dictation-profile `pre_roll_audio`, `speech_pcm_contract`, and `paste_restore_intent` coverage for the recorded WAV and paste restore contracts. The checker reads profile requirement and assertion lists from shared helpers, then composes doctor default assertions and proof-agent source-marker output from shared helpers so cloud, local-whisper, Notepad, and packaged-mock proof profiles cannot drift on install, doctor, listener, hold-hook, and native-adapter coverage. The `local-whisper-dictation` profile also requires `listener_runtime`, which archives a real installed listener run with `-Listen -MaxSessions 1` so the laptop proof covers the persistent listener path, not only one-shot dictate mode. Current profiles are `doctor-only`, `laptop-preflight`, `cloud-dictation`, `local-whisper-dictation`, `local-whisper-notepad-paste`, and `packaged-whisper-mock-install`. The real laptop profiles reject dirty packaged source provenance; dictation profiles also reject non-HTTPS, non-audio-transcription, loopback/mock, private, local, reserved, multicast, and documentation cloud endpoints, mock-looking whisper names, packaged executable backends, non-model local whisper paths, and contradictory clipboard restore/no-restore paste intent; only `packaged-whisper-mock-install` is allowed to use the artifact-local mock.
Use `check-windows-proof-set.ps1 -RequireFullLaptopProof` after the preflight report and three interactive laptop reports exist. It routes report paths through proof-set composition built by the shared proof helper, reuses the same report profiles, expected proof modes, required profile groups, profile-name validation, laptop-preflight handling, coverage requirement lists, and OK markers, verifies the reports came from the same GUID proof session, generated within the same 120-minute proof window, Windows machine, Windows user, package directory, package identity fingerprint, and source repository/branch/commit/dirty provenance, requires `source_dirty=false`, then prints `proof_set_ok=full-laptop`, so the final claim is one set-level proof instead of unrelated command outputs.

Package smoke writes native-only and local-whisper synthetic preflight reports, first validates each through the direct `check-windows-proof-report.ps1 -RequireProofProfile laptop-preflight` profile, then validates the wrapper path through `check-windows-proof-set.ps1 -RequireLaptopPreflight`. That keeps CI coverage on both the single-report profile interface and the set-level adapter.

For CI or artifact smoke only, pass `-UsePackagedWhisperMock` instead of explicit `-WhisperCLI` and `-WhisperModel`. The wrapper reads the artifact-local `whisper_cli_mock` entry from `manifest.txt` and uses the packaged agent executable as the mock model file; laptop proof should still pass real whisper.cpp paths or a real cloud endpoint/model. `check-windows-proof-set.ps1 -RequireArtifactSmokeProof` ties the doctor-only and packaged-mock install reports to the same Windows machine/user, package directory, package identity fingerprint, and clean source provenance before printing `proof_set_ok=artifact-smoke`.

Add `-CreateShortcut` to `install-windows-agent.ps1` after passing real endpoint/model/API-key args, whisper-cli/model args, or `-SkipSmoke` with an existing `-ConfigPath`. Add `-CreateStartupShortcut` for exact no-admin login start after choosing the cloud or local config you want at login; it writes that launcher/config shortcut into the current user's Startup folder unless `-StartupShortcutDir` is passed. The shared Windows permission surface now records this as `startup_launcher=run-windows-agent.ps1` plus `startup_launch_mode=listen`, matching the installer-created shortcut. The installer refuses to create a user shortcut for the default mock smoke config. The shortcuts point at the installed `run-windows-agent.ps1`, pass the exact `-InstallDir`, point at the same config path the installer just smoked, and pass `-Listen` so they launch the persistent listener instead of a single dictation session. CI package smoke uses the proof-only `-AllowSmokeShortcut` path, creates shortcuts in temporary folders, verifies their target arguments include the installed run script, install dir, config, and listener mode, and verifies the launcher with `-DoctorOnly`.

Windows agent config:

```powershell
swift run RomaWindowsAgent save-key-from-env --key groq --value-env GROQ_API_KEY
swift run RomaWindowsAgent write-config --endpoint https://api.groq.com/openai/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-name groq --hold-hook --paste --clipboard-restore-delay 2 --replace "just talk=roma-just-talk"
swift run RomaWindowsAgent config-doctor
swift run RomaWindowsAgent dictate
swift run RomaWindowsAgent write-config --whisper-cli C:\path\whisper-cli.exe --whisper-model C:\path\ggml-base.en.bin --hold-hook --paste --replace "just talk=roma-just-talk"
swift run RomaWindowsAgent config-doctor
swift run RomaWindowsAgent dictate
```

Use `--config C:\tmp\roma-agent.json` on `write-config` and `dictate` when you want an explicit config path instead of `%APPDATA%\roma-just-talk\windows-agent.json`. Paste restores the previous text clipboard by default; use `--no-restore-clipboard` to leave dictated text on the clipboard, or `--clipboard-restore-delay 0` for smoke tests that should not wait.

CI proof:

- `.github/workflows/romacore.yml` builds `RomaCore` on macOS and Windows.
- The Windows job verifies Visual Studio C++ tools, installs the official Swift toolchain with `winget install --id Swift.Toolchain`, then runs `windows-proof.ps1 -SkipMic`.
- `check-windows-scripts-parse.ps1` auto-discovers every proof `*.ps1` file and parses it in Windows CI, in the packaged artifact, and after install, so new proof scripts are covered without editing workflow-local or wrapper-local hard-coded parse lists. Packaged and installed proof runs also assert the parse count against the shared proof-surface file maps; installed proof reports record that count, and the checker requires it to match the shared installed map.
- Artifact-wrapper CI proof validates installed `config-doctor` output alongside the installed listener and launcher reports.
- CI is noninteractive, so it proves Windows compilation, PowerShell parse validity, pre-roll/WAV output, shared cleanup/replacement/paste text processing, clipboard restore option routing through source and packaged proof paths, DPAPI secret round-trip, stored-key transcription against a local mock STT endpoint, local `whisper-cli` argument shaping plus mock process execution, reusable `RomaWindowsAgent` config writing, hotkey/paste doctor paths, default `RegisterHotKey` availability, and the microphone-only OS permission grant split from no-prompt native capabilities. It does not prove real microphone permission, real hotkey delivery after a user presses the chord, local whisper inference, or paste into Notepad.
- CI also runs `package-windows-agent.ps1` on Windows only, requires Swift runtime DLLs in the artifact, rejects packaged artifacts whose shared manifest helper does not show `source_dirty=false`, parses the shared proof helper, packages the proof-only `RomaWhisperCLIMock.exe`, packages and smokes `RomaProofAgent.exe`, verifies the packaged `RomaWindowsAgent.exe` through `smoke-windows-agent.ps1`, smokes packaged listener mode with `listen --max-sessions 0`, asserts generated JSON config for both cloud endpoint/model and local whisper-cli modes, proves no-admin installs for both cloud/default and local whisper-cli config into temp directories, verifies the installed launcher with `-DoctorOnly`, creates a proof-only mock shortcut in a temp folder, creates a real local-whisper shortcut in a separate temp folder, verifies both native-only and local-whisper laptop preflight JSON checker shapes, including the archived permission-surface markers, through the shared preflight proof-shaping and output assertion helpers plus artifact package identity helper on the Windows runner, records the install config, shortcut paths, and both preflight-checker smoke reports in `manifest.txt`, requires both manifest report paths to exist through the shared manifest helper, smoke-tests moved-artifact relocation for the duplicate nested `preflight-proof.json` report names, packages and executes `prove-windows-agent-artifact.ps1 -DoctorOnly`, validates the packaged listener smoke, user-facing agent runtime wiring, proof-agent native adapter runtime and source-surface through shared source-marker helpers, and native-doctor reports through shared native-doctor command and marker helpers, runs the wrapper through the artifact-local manifest-backed local-whisper mock install, normal shortcut proof, startup shortcut proof, and installed launcher listener smoke, writes and validates a JSON wrapper proof report, and uploads a `roma-windows-agent` artifact for laptop smoke tests.

Raw command sequence:

```powershell
swift --version
swift build
swift run RomaCoreChecks
swift run RomaProofAgent doctor
swift run RomaWindowsAgent doctor
swift run RomaProofAgent pre-roll-proof --out core-proof.wav
swift run RomaProofAgent miniaudio-capture-doctor
swift run RomaProofAgent miniaudio-record-proof --out mic-proof.wav --seconds 2
swift run RomaProofAgent transcribe-proof-doctor
swift run RomaProofAgent whisper-cli-doctor
swift run RomaProofAgent whisper-cli-proof --audio mic-proof.wav --whisper-cli C:\path\whisper-cli.exe --whisper-model C:\path\ggml-base.en.bin --language en --prompt "roma just talk"
swift run RomaProofAgent dictation-pipeline-proof --out pipeline-proof.wav --text "hmm... just talk." --replace "just talk=roma-just-talk"
swift run RomaProofAgent dictation-pipeline-proof --out mid-sentence-proof.wav --text "Model." --preceding-text "...so this"
swift run RomaProofAgent transcribe-proof --audio mic-proof.wav --endpoint https://api.groq.com/openai/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-env GROQ_API_KEY
swift run RomaProofAgent windows-hotkey-doctor
swift run RomaProofAgent windows-hotkey-availability-proof
swift run RomaProofAgent windows-hotkey-proof
swift run RomaProofAgent windows-keyboard-hook-doctor
swift run RomaProofAgent windows-keyboard-hook-proof --timeout 15
swift run RomaProofAgent windows-paste-doctor
swift run RomaProofAgent windows-paste-proof --text "roma just talk proof" --focus-delay 5
swift run RomaProofAgent windows-paste-proof --text "roma just talk proof" --target-process-id 1234
swift run RomaProofAgent windows-permission-doctor
swift run RomaProofAgent windows-secret-doctor
swift run RomaProofAgent windows-secret-proof --dir C:\tmp\roma-secrets
swift run RomaProofAgent windows-secret-save-from-env --dir C:\tmp\roma-secrets --key groq --value-env GROQ_API_KEY
swift run RomaWindowsAgent save-key-from-env --key groq --value-env GROQ_API_KEY
swift run RomaWindowsAgent write-config --endpoint https://api.groq.com/openai/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-name groq --hold-hook --paste --clipboard-restore-delay 2 --replace "just talk=roma-just-talk"
swift run RomaWindowsAgent write-config --whisper-cli C:\path\whisper-cli.exe --whisper-model C:\path\ggml-base.en.bin --hold-hook --paste --replace "just talk=roma-just-talk"
swift run RomaWindowsAgent dictate
swift run RomaWindowsAgent dictate --hold-hook --endpoint https://api.groq.com/openai/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-name groq --paste --no-restore-clipboard
swift run RomaProofAgent transcribe-proof --audio mic-proof.wav --endpoint https://api.groq.com/openai/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-name groq --secret-dir C:\tmp\roma-secrets
swift run RomaProofAgent windows-dictation-proof --out dictation-proof.wav --seconds 2 --endpoint https://api.groq.com/openai/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-env GROQ_API_KEY --replace "just talk=roma-just-talk" --paste
swift run RomaProofAgent windows-dictation-proof --out hold-dictation-proof.wav --hold-hook --timeout 15 --endpoint https://api.groq.com/openai/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-env GROQ_API_KEY --paste
swift run RomaProofAgent windows-dictation-proof --out local-hold-dictation-proof.wav --hold-hook --whisper-cli C:\path\whisper-cli.exe --whisper-model C:\path\ggml-base.en.bin --paste
powershell -ExecutionPolicy Bypass -File .\Scripts\package-windows-agent.ps1 -OutputDir C:\tmp\roma-windows-agent
```

User-facing Windows agent proof:

```powershell
powershell -ExecutionPolicy Bypass -File .\Scripts\windows-proof.ps1 -RunInteractiveWindowsAgent -UseHoldHook -PasteDictation -TranscribeEndpoint https://api.groq.com/openai/v1/audio/transcriptions -TranscribeModel whisper-large-v3-turbo -TranscribeApiKeyEnv GROQ_API_KEY -WordReplacement "just talk=roma-just-talk"
powershell -ExecutionPolicy Bypass -File .\Scripts\windows-proof.ps1 -RunInteractiveWindowsAgent -UseHoldHook -PasteDictation -WhisperCLI C:\path\whisper-cli.exe -WhisperModel C:\path\ggml-base.en.bin -WordReplacement "just talk=roma-just-talk"
```

Manual proof:

- Start the agent.
- Say "before hotkey".
- Toggle proof: press the configured shortcut, say "after hotkey", and wait for the configured duration.
- Hold proof: hold the configured shortcut while speaking, then release it.
- Verify `proof.wav` contains both phrases.
- Verify transcription contains both phrases.
- Verify paste lands in Notepad.

Do not claim Windows support until the audio, transcription, and paste proof all pass on a real Windows machine.

## What Not To Do

- Do not rewrite the product from scratch in Electron just to get a Windows window.
- Do not port every SwiftUI settings/history screen before recording and paste work.
- Do not make Windows support depend on screen capture or app-aware context first.
- Do not treat local-vs-cloud STT as the thesis. The thesis is pre-roll capture and speak-before-hotkey.
- Do not make macOS worse while extracting core; macOS stays the proving ground until Windows proof exists.

## References

- Swift Windows install: https://www.swift.org/install/windows/
- Swift Package Manager: https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/
- miniaudio manual: https://miniaud.io/docs/manual/index.html
- whisper.cpp: https://github.com/ggml-org/whisper.cpp
- WASAPI capture: https://learn.microsoft.com/en-us/windows/win32/coreaudio/capturing-a-stream
- RegisterHotKey: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerhotkey
- SetWindowsHookEx: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowshookexa
- LowLevelKeyboardProc: https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelkeyboardproc
- KBDLLHOOKSTRUCT: https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-kbdllhookstruct
- CallNextHookEx: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-callnexthookex
- SendInput: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput
- CryptProtectData: https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata
- CryptUnprotectData: https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptunprotectdata
- Windows microphone privacy: https://support.microsoft.com/en-us/windows/windows-camera-microphone-and-privacy-a83257bc-e990-d54a-d212-b5e41beba857
