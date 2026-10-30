# Disposable virtual camera probe

This CI-only probe installs unchanged, publisher-signed OBS 33.0.1 on a fresh GitHub-hosted ARM64 Mac. It verifies the DMG hash and signatures, requests the modern camera extension, and tries ordinary System Settings controls. It signs a dedicated UI helper and grants only that helper Accessibility on the fresh disposable host, using its exact designated requirement. Existing helper grants are never replaced. SIP, Gatekeeper, passwords, and system-extension approval policy stay unchanged. Secure authentication fields are detected without reading or entering their values.

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
