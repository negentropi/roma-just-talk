# Disposable virtual camera probe

This CI-only probe installs unchanged, publisher-signed OBS 33.0.1 on a fresh GitHub-hosted ARM64 Mac. It verifies the DMG hash and signatures, requests the modern camera extension, and tries ordinary System Settings controls. It signs a dedicated UI helper and grants only that helper Accessibility and event posting on the fresh disposable host, using its exact designated requirement. Existing helper grants are never replaced. SIP, Gatekeeper, passwords, and system-extension approval policy stay unchanged. Secure authentication fields are detected without reading or entering their values.

A pinned public CREMA-D clip is stripped of audio and played in an OBS Media Source. The native helper enumerates AVFoundation devices, selects OBS, captures video-only pixel buffers, counts frames and distinct sampled-pixel hashes, then closes capture. `supportedDeviceReady` requires at least 25 frames, 10 distinct frame hashes, no audio input, and stopped capture. This is camera-device proof, not Roma insertion or the application's movie-writer lifecycle.

The workflow uploads actual screenshots, bounded AX trees, extension states, camera receipts, OBS logs, and exact source head. It fails the final gate if setup or capture is blocked. Missing permissions, an unavailable authentication credential, a disabled extension, and a static feed cannot become a pass.

Sources:

- [OBS activation and macOS compatibility](https://obsproject.com/kb/virtual-camera-troubleshooting).
- [OBS launch parameters](https://obsproject.com/kb/launch-parameters).
- [OBS WebSocket protocol](https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.json).
- [Publisher release 33.0.1](https://github.com/obsproject/obs-studio/releases/tag/33.0.1).
- [Apple system-extension requirements](https://developer.apple.com/documentation/systemextensions).

Run only through `.github/workflows/lip-camera-probe.yml` on its disposable `ci/lip-camera-probe-*` branch. No heavyweight local build is needed.

Set `LIP_CAMERA_PROBE_KEEP_OBS_RUNNING=1` to retain OBS and its feed after a successful device probe for a following app E2E step. The receipt records `obsRetainedForE2E`. Blocked probes still request normal shutdown. The local OBS WebSocket configuration contains a private random password; subsequent local tooling may read it, but must never log or upload it.

After extension approval, the probe requests the documented OBS restart and verifies that the probe-owned process actually exits. An AppleEvent error alone cannot override observed shutdown. It waits for the new process's WebSocket endpoint, authenticates, and requires successful frontend and virtual-camera status responses before capture. RPC receipts are saved after every response, including failures, so a static camera placeholder cannot substitute for active output.

A delayed OBS camera-not-installed alert can block that restart even after the extension is enabled. The probe requests normal quit first and observes the exact owned PID. Only a blocked quit triggers the signed-OBS helper, which requires the exact critical alert text/image and one enabled **OK** button. It presses once, then requires that matched alert instance to disappear from readable `AXWindows` before one further normal quit and PID-exit observation. Unrelated Qt windows may omit optional Description. Bounded receipts retain window facts and raw AX errors; no matching alert, ambiguous candidates, an unreadable observation, or a surviving process blocks acceptance.

`LIP_CAMERA_PROBE_USE_HOST_AUTOLOGIN_AUTH=1` permits one normal GUI authentication attempt on the disposable GitHub macOS host. The helper requires `GITHUB_ACTIONS=true` and `RUNNER_OS=macOS`, the Apple-signed SecurityAgent at its system path, the exact observed System Extensions prompt, and the current account's username or full name. It reads only the existing root-owned `/etc/kcpassword` into process memory, verifies its decoded credential against that exact local account through OpenDirectory, requires the unique secure field to belong to that signed process and advertise a writable value, then writes directly to that exact field and submits through the ordinary GUI button. Credentials never enter arguments, environment variables, new files, logs, or artifacts. A per-run marker prevents another attempt. Secure text values are never inspected, and no screenshot is taken between typing and submission. Only the extension's actual enabled state and later captured frames can satisfy the gate.

This credential source is documented by GitHub's own image builder. The [macOS26 ARM64 template](https://github.com/actions/runner-images/blob/9329c776c4a38d3dcb31fc78b8180005041c07fb/images/macos/templates/macOS-26.arm64.anka.pkr.hcl) passes its sensitive VM password to [configure-autologin.sh](https://github.com/actions/runner-images/blob/9329c776c4a38d3dcb31fc78b8180005041c07fb/images/macos/scripts/build/configure-autologin.sh), which invokes the [published bootstrap encoder](https://github.com/actions/runner-images/blob/9329c776c4a38d3dcb31fc78b8180005041c07fb/images/macos/assets/bootstrap-provisioner/kcpassword.py). The probe uses the existing host credential, never a guessed default or a password reset.
