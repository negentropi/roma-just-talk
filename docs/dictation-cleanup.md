# Choose dictation cleanup

In **models**, open the settings gear and choose **Custom** or **None** under **Dictation Cleanup**. Settings opens in a Mac sheet; use its close button or Escape to return.

Custom keeps the existing formatting, filler words, dictionary, snippets and AI enhancement settings. It is the default for existing installations.

None keeps the exact text returned by the transcription model. It skips cleanup filters, snippets, dictionary replacements, prompt triggers and AI enhancement. It also skips cursor capitalization and added trailing spaces. Your libraries and Custom settings stay saved. The inactive formatting controls show those saved values; choose Custom to use them again.

The choice applies globally, including Power Modes, imported audio and retranscription. A recording captures the choice when it starts. Each imported file and retranscription captures it when processing begins. Changing the choice affects the next operation.

Dedicated Translate, Edit and Draft Writing Actions keep their separate behavior and still use AI. None controls ordinary dictation. It does not change the recognition model, language, VAD or model prompt.

None saves the model's returned text in the existing Original History variant. It cannot recover recognition text discarded by older recordings. Empty or whitespace-only recognition inserts nothing and does not paste an older transcript through the Special shortcut fallback.

Settings backup includes the choice. Importing an older backup without it leaves the current choice unchanged. Switching profiles preserves saved settings and libraries. The existing full data reset retains its normal deletion behavior.

## Verification status

Matched old/new pipeline checks and one real Whisper file import passed on remote macOS. Shared Core also passed the iOS Simulator compile. The [current unit plan](research/competitors/raw-profile-plan.md) tracks a shared settings-panel accessibility defect found by native UI testing; profile selection and relaunch persistence still require a passing rerun, followed by the full Mac Release gate. The earlier verified writing/snippet artifact predates this option. Light, Clarity and per-mode profiles remain later work.
