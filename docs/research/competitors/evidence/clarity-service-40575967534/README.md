# Clarity whole-bundle pretest signature failure

[Run 40575967534](https://github.com/negentropi/roma-just-talk/actions/runs/40575967534), source `de15a9bb39cfc9e06d0ef0196a1eb19692876159`: the actual eleven-source library, seven unchanged tests, and standard Swift Testing runner compiled and linked in **194.78 s**. All 26 service pins matched the canonical app subset before and after compilation.

**No tests ran.** Strict deep verification of the whole generated `.xctest` bundle returned `code has no resources but signature indicates they must be present`. The previous correction from the inner executable to the whole bundle was insufficient. This is pretest fixture/signing failure, not evidence of a failing Clarity API assertion.

The artifact lacks a pre-verification bundle file census and detailed signature display, so it cannot identify the precise resource-seal defect. Further diagnosis should inspect native SwiftPM test-bundle signing preparation using a tiny SDK-only test package before another full dependency build. No signing bypass, test weakening, or source correction is established here.

The 77,115-byte artifact was downloaded once and verified by size/SHA-256; original files are in `artifact/`. The failed log was fetched once. `receipt.json` records the exact boundary. No seven-test success, app/UI, provider/credential, or AI-quality claim follows from this run.
