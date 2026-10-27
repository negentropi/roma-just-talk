# Matched literal-rule Core proof

[Run 40571902653](https://github.com/negentropi/roma-just-talk/actions/runs/40571902653), candidate `808c1a36609a05a20744c6a7a3abad7fce5715bb`, baseline `919670ae5b918afbfad6f4d88982a481c1c4b532`.

Both actual Core versions executed all 1,721 checks with the same 14 JSON-based literal tests and exact runner bytes. Baseline exited 1: all 1,707 earlier checks passed, three new control methods passed, and eleven literal methods failed with 23 retained source assertions. Candidate exited 0 with all 1,721 checks passing. Old code compiled and ran; missing APIs, setup failures and skipped checks do not account for the difference.

The old failures cover literal commas, terminal replacements, overlapping/protected source spans, strict matching-kind data, kind-preserving edits and legacy export exclusion. Existing sequential comma behavior stays a passing control. Non-spaced canonical matching also passes on both the old production policy and candidate; the earlier draft's separate canonical-matching defect has its own smaller proof.

Actual resolved dependency checkouts match all 22 frozen pins and have no tracked changes. The local Core/NVIDIA source census, modes, oracle, package locks and verification helpers stayed unchanged. Both runs used distinct fresh scratch builds. Toolchain before and after agrees: Xcode 26.6, Swift 6.3.3, macOS 26.6.2, arm64.

The 302,038-byte artifact was downloaded once and matched GitHub's SHA-256 `b33519e0a78548f055a2f04a2b343d55fc089ea18adbf199d736aa48ddc71726`. All ZIP members passed CRC checks. Original logs, source/graph records and oracle files remain under `artifact/`. Run `python3 docs/research/competitors/evidence/literal-rules-40571902653/analyze-result.py` from the repository to independently check registrations, assertions, source blobs and retained hashes.

Independent read-only review reran the analyzer and checked the raw logs, fixture assertions, immutable source, registrations, pins and toolchain. No findings; details in `independent-review.json`.

This is Core policy and codec proof. It does not expose approved corrections in the app or establish approval UI, full-record backup, SwiftData upgrade, iOS downgrade safety, provider behavior or universal linguistic segmentation. The unrelated automatically triggered iOS run was canceled by the parent; no iOS build result is claimed.
