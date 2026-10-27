# Clarity semantic probe build

[Run 40577497741](https://github.com/negentropi/roma-just-talk/actions/runs/40577497741) passed at exact source `18552122392a0d161969074b1ff2361d1a9a5517`. Actual native compilation and linking completed with Xcode 26.6 and Swift 6.3.3 on arm64 macOS 26.6.2. CI verified the unique ad-hoc signed app with `codesign --verify --deep --strict`.

Independent audit matched 173 committed inputs, eleven service source files, 155 Core/NVIDIA source hashes, the generated driver, and all 26 canonical dependency checkouts. Both GitHub artifact ZIP digests and the complete signed bundle match. NVIDIA's inner lock contributes 22 identities; the app lock supplies the exact 26 service pins. Seven inner-lock version differences are recorded rather than treated as app-pin mismatches.

This is build and artifact-identity evidence. CI made zero semantic calls. No provider authentication, app lifecycle, pipeline, microphone, editor or UI execution occurred. Linux byte inspection does not replace fresh Mac signature verification before the later run. Model identity, outputs and independent semantic grading remain pending.

Full artifacts remain on `decentleftover-pf` under `/data/codex/rjt/clarity-semantic-build-40577497741/`. The 7,777,625-byte signed archive is staged at `/tmp/rjt-clarity-semantic-probe-40577497741/signed-probe.tar.gz`, still unextracted. Its SHA-256 is `5446e2311edaf0e7335a30eae11da0e1f865c81039cad5e488fc4f0179d94178`.
