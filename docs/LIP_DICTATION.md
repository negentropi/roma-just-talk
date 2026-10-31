# Lip dictation

Lip dictation is off by default. In Settings, choose **Set Up** under **Lip Dictation**. Setup asks for camera access and downloads the recognition model. Setup does not turn the feature on.

Turn on **Read Lips While Dictating** to record the camera and microphone with the usual recording shortcut. Both recognizers run for that recording. Roma uses the voice transcript when it contains speech and uses lip reading when it does not. Ready voice text cancels unused lip recognition and waits for its cleanup before insertion. Roma inserts one result through the usual dictionary, text cleanup, enhancement, history, and paste flow.

Under that toggle, **Lips Only** uses the camera with microphone capture and microphone pre-roll suspended. It does not require an audio recognition model or microphone permission. Turning the master toggle off returns to ordinary voice dictation, including its existing microphone pre-roll behavior.

## Setup and limits

- macOS 14.4 or later. Camera access is separate from microphone access.
- The model download is about 1.98 GB. Installed model storage is about 1.36 GB. Installation temporarily needs both, plus working space.
- Experimental English recognition. Use short phrases, face the camera in good light, and keep other faces out of view. Maximum recording length is 60 seconds.
- Lip movements cannot distinguish every sound. Recognition can misread words, names, and numbers. Review the inserted text.
- Settings show setup failures and camera permission recovery. The recording shortcut does not download models or ask for camera access.

## Privacy and cancellation

The camera opens only for an enabled recording. Stop closes capture before recognition. Cancel, disable, and normal app termination cancel the owned camera and inference work. Temporary video is local and is removed after that operation finishes. Video is not stored in transcription history.

Lip recognition runs locally. The optional existing enhancement feature retains its selected provider and privacy behavior. In combined mode, the selected voice model also retains its existing local or cloud behavior.

## Model and reproduction

The implementation uses the original [RAVEn/BRAVEn release](https://github.com/ahaliassos/raven/tree/9fd9a3743c41ba93532258b340d123c20fe25432), whose project license is MIT. The app installs the publisher-linked Large checkpoint and verifies its original bytes before extracting a fixed list of tensor files. It does not require Python or load pickle objects. Learned weights are downloaded during setup rather than included in the app.

The exact publisher URL, SHA-256 hashes, storage entries, license scope assessment, preprocessing reference, exporter, and parity evidence are retained with [the native package](../VoiceInkLip/Tools/BRAVEn/README.md). Applying the project's MIT license to its externally linked checkpoint is an inference; the publisher does not supply a separate checkpoint license statement. This must remain visible in the commercial-use review. LipFlow's restricted Auto-AVSR weights and AV-HuBERT derivatives are not used.

The `LipDictationProof` executable exercises the same native video preprocessing and recognition used by the app. Its CI receipts distinguish silent-video recognition from app capture, microphone isolation, and insertion tests. A passing decoder or geometry test alone does not verify dictation.
