# Lip dictation readiness

Research snapshot: 2026-10-27, Asia/Taipei. RJT source inspected at `9e35e991`.

Lip dictation is not implemented. The requested behavior is defined below, but integration is blocked on a commercially usable recognition model or SDK. No model was downloaded, camera activated, vendor contacted, or runtime claim established during this research.

## Requested behavior

The feature defaults to off. Its default enabled mode is simultaneous voice and lip dictation. A nested setting selects lip-only dictation.

| Effective mode | Microphone | Camera | Activation |
| --- | --- | --- | --- |
| Voice only, default | Existing voice capture and pre-roll behavior | Closed | Existing dictation shortcut |
| Voice and lip | Voice capture | Lip capture | Both start within the same shortcut session |
| Lip only | Closed, including idle pre-roll | Lip capture | Existing dictation shortcut |

The proposed runtime data shape is one effective mode with these three cases. Persisted preferences must resolve to a valid mode. A remembered lip-only choice has no effect while the feature is off, which restores ordinary audio behavior. No lip-specific global shortcut is required.

The selected mode is fixed when a session starts. Mode changes apply after current work finishes safely. Turning the feature off during a lip-enabled session cancels that session, suppresses its result, and closes the camera before restoring ordinary audio behavior. This exception prevents a disabled feature from continuing capture.

The session produces at most one text insertion and one completed history entry. Both capture paths share stop, cancellation, error recovery, and session identity. A canceled or superseded session cannot paste a late recognition result.

## Commercial model gate

The code license and pretrained-model terms are separate. An MIT or Apache label on a wrapper does not establish commercial rights for its required weights.

The following candidates were checked. This is a targeted search, not proof that no suitable commercial model exists.

| Candidate | Primary evidence | Current decision |
| --- | --- | --- |
| LipFlow and its Auto-AVSR weights | LipFlow's [pinned NOTICE](https://github.com/amywork777/lipflow/blob/e37453b1e1e125ca7130e4abf2635117635f6e0b/NOTICE) treats downloaded LRS3 model weights as non-commercial research. | Excluded under the commercial requirement. The MIT application code does not remove the model restriction. |
| MSP-VSR | The [model card](https://huggingface.co/MahmoodAnaam/MSP-VSR) identifies an AV-HuBERT base despite its Apache label. The [original AV-HuBERT license](https://github.com/facebookresearch/av_hubert/blob/main/LICENSE) restricts commercial and production use, including derivatives. | Not cleared for commercial integration. |
| Whisper-Flamingo | [Audio-visual decoding instructions](https://github.com/roudimit/whisper-flamingo#audio-visual-decoding) require AV-HuBERT weights. Its [license file](https://github.com/roudimit/whisper-flamingo/blob/main/LICENSE) includes the inherited restrictions. | Not cleared for commercial integration. |
| VALLR | The [official repository](https://github.com/MarshallT-99/VALLR#license) declares CC BY-NC 4.0. | Excluded under the commercial requirement. |
| Interfaces Silent Speech | The [partner page](https://www.interfaces.inc/partners) advertises licensing, camera-only silent speech, audio-visual enhancement, and Mac support. API access is early and invite-based. | Commercial lead only. No SDK, model, API access, or applicable commercial contract was obtained or verified. |

Interfaces' public [research agreement](https://www.interfaces.inc/research-agreement) requires participation in its preview research. Covered data includes face and mouth video, audio, and derived information. The agreement permits research use of covered information and says an integrator must obtain the required end-user permissions. These preview terms do not establish a suitable commercial RJT agreement. No agreement was accepted and no customer recordings were submitted.

The next dependency is a specific checkpoint with documented commercial rights, or a vendor SDK or API with an applicable commercial agreement and test access. The evidence must cover the required visual encoder, decoder, model assets, deployment, and redistribution. A price page or permissive wrapper license is insufficient.

## Existing RJT integration points

These are observed source facts. The changes described afterward are proposed.

| Current owner | Observed behavior | Required integration |
| --- | --- | --- |
| [`RecorderUIManager.toggleMiniRecorder`](../../VoiceInk/Transcription/Engine/RecorderUIManager.swift) | Owns the logical recorder session and calls the engine for start, stop, and cancellation. | Keep one session for both inputs. Do not add competing shortcut handlers. |
| [`VoiceInkEngine.toggleRecord`](../../VoiceInk/Transcription/Engine/VoiceInkEngine.swift) | Requires a selected audio model and microphone permission before recording. Uses a start identity and defers stop during startup. | Select resources from the effective mode. Lip-only must bypass audio-model and microphone requirements. |
| [`Recorder`](../../VoiceInk/Recorder.swift) and [`VoiceInk.swift`](../../VoiceInk/VoiceInk.swift) | Start microphone pre-roll at launch and after an idle audio-device change. | Lip-only must stop existing pre-roll and prevent its restart, including device changes and relaunch. Skipping only `startRecording` is insufficient. |
| [`VoiceInkEngine.stopRecordingAndRunPipeline`](../../VoiceInk/Transcription/Engine/VoiceInkEngine.swift) | Stops the audio recorder and expects a recorded audio file before it creates a pending transcription. | Lip-only needs a real video or text-result path, without fabricated audio files. |
| [`TranscriptionPipeline`](../../VoiceInk/Transcription/Engine/TranscriptionPipeline.swift) | Transcribes audio, then applies cleanup, dictionary replacement, enhancement, paste, and history persistence. | Reuse the text-processing and insertion path once. Separate input recognition from text processing where needed. |
| [`AppDefaults`](../../VoiceInk/AppDefaults.swift) and [`UserDefaultsPreferences`](../../VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift) | Register preference defaults and shared settings policy. | Add default-off lip preferences and a tested effective-mode policy. Keep OS capture and permissions in the macOS shell. |

The existing pipeline uses transcription identities to suppress stale state changes and paste after cancellation. Lip inference must obey the same session ownership rule. Reset, recorder dismissal, and application termination must also close active camera resources.

The app currently has no camera usage description in [`Info.plist`](../../VoiceInk/Info.plist). Both [`VoiceInk.entitlements`](../../VoiceInk/VoiceInk.entitlements) and [`VoiceInk.local.entitlements`](../../VoiceInk/VoiceInk.local.entitlements) lack the camera entitlement. Integration must add `NSCameraUsageDescription` and verify the required `com.apple.security.device.camera` resource entitlement and permission flow in the actual signed app. These source omissions alone do not establish how the current unsandboxed app would behave at runtime.

## Recognition and capture contract

RJT owns native capture, permissions, shortcut handling, cancellation, and insertion. A recognition backend must not register its own hotkeys, paste text independently, or import another application's history.

The camera remains closed while lip dictation is disabled or idle. Capture closes on stop, cancel, disable, startup failure, and termination. Any model requirement for capture after release needs an explicit, visible, bounded design before adoption. Temporary video is deleted after inference or cancellation unless the user separately selects retention.

Lip-only keeps the microphone and audio pre-roll off for as long as that mode is selected, including between sessions. This covers launch, queued startup, audio-device changes, recovery, and cleanup. Suspending audio clears retained PCM and prevents an obsolete queued task from restarting capture. Returning to a voice-enabled mode restores the existing pre-roll policy. The recorder UI must identify the active input mode and camera capture state.

Missing models, unsupported hardware, denied camera permission, restricted camera permission, camera removal, and recognition failure need actionable errors. A lip-enabled session must not silently start as voice-only. Camera permission requests belong to explicit setup or recovery, so the dictation shortcut does not open a prompt and steal focus. Recovery leaves camera capture closed and applies the effective mode's microphone policy.

Simultaneous activation does not by itself establish audio-visual fusion. A fusion model consumes aligned audio and video and returns one hypothesis. Independent voice and lip recognizers need a tested rule for selecting one result. Concatenating both transcripts duplicates dictation. The backend evaluation must settle this choice before implementation, including what happens when one recognizer fails or disagrees.

Supported languages come from the selected backend and verified tests. The LipFlow reference uses English vocabulary and does not establish multilingual lip dictation. No language or accuracy claim transfers from RJT's existing audio models to a visual model.

A cloud backend requires a clear provider and data-flow choice before capture can upload video. Enabling lip dictation must not silently upload face video, enable research participation, or change an existing local voice-model choice. Commercial terms, retention, training use, and deletion behavior must be established before customer use.

## Planned settings UI

Claude Opus 5.5 proposed a **Lip Dictation** toggle, off by default, in the existing native settings form. Enabling it expands a nested **Lips only** toggle, also off by default. This preserves simultaneous voice and lip activation as the normal enabled mode.

Review was requested from GPT-6.1 Sol. The review returned contract corrections, but its runtime model identity was not independently verified. The proposal still needs the licensed backend's actual setup and permission behavior before UI implementation. It promises no camera warmup or pre-roll. This is a future design, not a shipped settings control. No nonfunctional feature toggle is added while the runtime dependency is unresolved. The design review provides no runtime proof.

## Verification status

The completed evidence is source inspection and primary-source research. Runtime evidence remains absent.

| Check | Status on 2026-10-27 | Required proof before acceptance |
| --- | --- | --- |
| LipFlow model terms | Checked at the pinned commit | A replacement's exact weights and commercial terms must be recorded. |
| Existing session, microphone, and pipeline ownership | Source inspected at `9e35e991` | Exercise the changed app through the actual shortcut and text insertion. |
| Default-off behavior | Required, not implemented | Fresh preferences and upgrade preserve voice behavior, with no camera access or lip runtime activity. |
| Simultaneous activation | Required, not implemented | Capture timestamps show both inputs belong to the same session. One transcript is inserted once. |
| Lip-only microphone isolation | Required, not implemented | Microphone capture and pre-roll remain stopped through launch, queued startup, device changes, recovery, cleanup, and dictation. Retained PCM is cleared. No microphone permission request occurs. The orange privacy indicator alone is insufficient proof. |
| Silent dictation quality | Not tested | Use rights-cleared, answer-hidden clips and real webcam sessions. Test silence, ordinary mouthing, face loss, lighting, unsupported languages, and false text generation. |
| Stop and cancellation | Required, not implemented | Test stop during startup, cancel during capture and inference, disable mid-session, repeated activation, and a delayed old result. No canceled text is inserted. |
| Permissions and failures | Required, not implemented | Test fresh camera permission, denial, restriction, recovery, camera removal, missing runtime, and failed inference in the signed macOS app. |
| Resource and latency behavior | Not measured | Record cold and warm latency, active and idle CPU, memory, and camera lifetime on supported Macs. Agree acceptance limits from the actual backend and product requirements. |
| Existing voice behavior | Not retested | Run relevant shared checks, macOS build and tests, and actual voice dictation with the lip feature off. |

No build, automated test, or runtime verification was run for this documentation-only snapshot. None is presented as proof of lip dictation.

## Unsent commercial-access inquiry

Status: draft only. No message has been sent.

To: `hello@dafdef.com`, published on the [Interfaces partner page](https://www.interfaces.inc/partners).

Subject: Commercial macOS silent-speech SDK or API access for Roma Just Talk

Hello Interfaces team,

Roma Just Talk is a macOS dictation app. We are evaluating commercially licensed lip dictation with two modes: camera-only silent dictation, and simultaneous microphone plus camera dictation. Both would use the app's existing shortcut and produce one transcript.

Could you provide details on the following points?

1. Is a macOS SDK, local runtime, or documented API available for evaluation? Can we obtain sandbox access and integration documentation?
2. Does recognition support free-form speech, or only fixed phrases? Which languages, hardware, frame rates, camera positions, and clip lengths are supported?
3. Are camera-only recognition and synchronized audio-visual recognition both available? How does the API handle partial results, end-of-speech, cancellation, and failure of one input?
4. What commercial deployment and redistribution rights are available for the model, required encoders, and SDK? Can you document their provenance and confirm whether any research-only assets are required?
5. Can processing stay on the Mac? For cloud processing, what data is transmitted, retained, used for training, or shared? Is a contractual training opt-out available, and how does deletion work?
6. What license, usage charges, minimum commitments, and commercial support terms apply?
7. What measured cold and warm latency, active memory, idle memory, CPU, and GPU requirements can you share for supported Macs?

We would first test with rights-cleared recordings. We need applicable commercial terms and technical access before deciding on integration.
