# Clarity pretest signature fixture failure

[Run 40575108782](https://github.com/negentropi/roma-just-talk/actions/runs/40575108782), source `46d5e2839cf50dfdcde4bdca79da8188e3b95299`: the actual eleven-source `VoiceInk` library, unchanged seven-test source, and standard Swift Testing runner compiled and linked in **96.68 s**. All 26 resolved service pins matched the canonical app subset before and after compilation.

The run is **invalid for runtime acceptance**: no tests ran. The fixture tried to verify the inner `.xctest/Contents/MacOS/ClarityServiceCheckPackageTests` executable as standalone code. The retained diagnostic is `code has no resources but signature indicates they must be present`.

The correction verifies and displays the complete `.xctest` bundle before and after the tests, using `--deep --strict`. Actual executable hashes, full bundle/resource manifests, descriptor equality, and the strict seven-test classifier remain intact. No signing or resource-check bypass was added. Apple's [Code Signing Tasks](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html) describes bundle resource sealing; [TN2206](https://developer.apple.com/library/archive/technotes/tn2206/) documents deep bundle verification. The retry must establish that the complete bundle passes verification.

The 77,067-byte artifact was downloaded once and its size/SHA-256 verified. `artifact/` retains the original sources and logs; `receipt.json` records the precise boundary and limits. The failed CI log was fetched once. This run proves no seven-test success, app/UI behavior, provider/credential behavior, or AI output quality.
