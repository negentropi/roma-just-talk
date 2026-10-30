# BRAVEn model assets

The app bundles a source-only ONNX graph, tokens, face geometry, and notices. Learned neural weights come from the original publisher after model installation is requested.

| Artifact | Pin |
| --- | --- |
| Publisher source | `ahaliassos/raven` at `9fd9a3743c41ba93532258b340d123c20fe25432` |
| Model | High-resource BRAVEn Large with self-training, LRS3+Vox2-en+AVS |
| Publisher checkpoint SHA256 | `8dd3bbf4e8d6287e87e7c3d9bc65f6238b4d75b12040e10f5589e3c6e76bda8f` |
| Publisher download | 1,975,266,407 bytes |
| Installed publisher storage | 1,361,670,500 bytes across 658 entries |
| Source graph | 910,911 bytes, SHA256 `0d98db3a949252b205cbc1fc57dee372ed61243aaf917ec684fde26c05e39f29` |

`provenance.json` records transferred artifact hashes and source URLs. `Upstream/` retains the actual pinned publisher README and MIT license, vocabulary, and face reference. The runtime dependency's license sources are also retained. Runtime notices live in `Sources/VoiceInkLip/Resources/ThirdParty/`.

## Commercial-use evidence

The publisher's [root MIT license](https://github.com/ahaliassos/raven/blob/9fd9a3743c41ba93532258b340d123c20fe25432/LICENSE) permits commercial use and redistribution under its notice condition. The [same repository README](https://github.com/ahaliassos/raven/blob/9fd9a3743c41ba93532258b340d123c20fe25432/README.md#braven-high-resource) directly links this checkpoint. No code-only carveout or conflicting checkpoint restriction appeared in the inspected README, LICENSE, or publisher file view.

The publisher does not separately state a license for standalone weights. Applying project MIT to its linked weights remains an inference. Dataset names alone did not establish a model-use restriction. This artifact does not include AV-HuBERT or USR2 model weights. Apache notices from the original ESPnet-derived code are preserved.

ONNX Runtime 1.24.2 is MIT. Its original license and full upstream third-party notices are bundled. This records the dependency already selected by `Package.swift`; the export evaluation used ORT 1.20.1.

## Verification boundary

`verify_assets.py` checks the checked-in graph, manifest, token vocabulary, exact face geometry, notice hashes, and safe storage paths. It reads ONNX metadata without loading external weights. Its developer dependency is `onnx`, verified with 1.17.0.

```sh
python3 VoiceInkLip/Tools/BRAVEn/verify_assets.py
```

`Proof/` contains the actual remote outputs. Dynamic positional encoding produced bit-identical Torch logits to the original cached table. All 401 frame argmaxes and all seven CTC outputs matched between Torch and ORT. Strict logprob tolerance `rtol=1e-4, atol=1e-4` passed six cases and failed `b-frozen`. Maximum logprob drift was `0.006383`; the clip still decoded blank. Disabling ORT optimizations did not close this gap. These facts do not establish broad dictation accuracy or native camera-to-text correctness.

## Recorded export layout

The supplied scripts preserve the evaluated build. Their disposable working directory is `raven/large/`, beside the pinned checkout in `raven/upstream/`. That directory contains the original checkpoint named `braven-large-self.pth`, six answer-free replay tensors named `a-intact-tensor.pt` through `c-frozen-tensor.pt`, and their frozen `*-pytorch-logits.pt` outputs from the original Torch run. No replay video, tensor, or learned neural weight is committed here.

`export_ctc.py` verifies dynamic positional encoding against original Torch outputs and exports standard ONNX opset 17 with constant folding disabled. `externalize.py` byte-compares every initializer against the publisher's original ZIP storage and creates the source-only graph and installation manifest. `verify_ort.py` records numerical and CTC parity. The scripts enforce four CPU threads and an 8 GiB process address-space limit. Their pinned environment was Torch 2.5.1 CPU, ONNX 1.17.0, and ORT 1.20.1.

The native installer reads only the bundled storage whitelist after verifying the entire original checkpoint hash. It ignores pickle metadata. No Python runtime is required by the app.
