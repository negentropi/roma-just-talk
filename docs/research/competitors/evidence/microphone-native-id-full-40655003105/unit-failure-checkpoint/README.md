# Full-run Core, unit, native and Release checkpoint

[Run 40655003105](https://github.com/negentropi/roma-just-talk/actions/runs/40655003105) completed successfully at tested head `0184f9a1552d281cd6b416446b92e091b6bdad29` in normal `full` mode. The retained metadata records successful Core, package, ordinary unit, initial native, matched regression, UI/persistence, Release packaging and app-upload steps. This checkpoint audits Core, package, unit, the six initial native cases, literal-snippet regression and Release evidence. The parent folder separately audits the eight UI cases, microphone handling and post-UI persistence checks.

| Boundary | Actual retained result |
| --- | --- |
| Core | 1,758 unique `PASS` names in exact registry order, matching terminal count, no `FAIL` |
| Package resolution | All 41 complete expected pins; canonical SHA `bfb9034a29dce69e0c9197557726fd20b17dfc018e626ebb431e306982cfb98f`; strict resolution exited zero and preserved the lock |
| Ordinary units | 330 unique Swift Testing identifiers: 299 `Success`, 31 `Skipped`; nine Onboarding XCTest identifiers all `Success` |
| Focused units | 44 concrete `Success` records, no issue; all 29 correction records also succeed, with seven overlapping identifiers |
| Initial native checks | Six unique cases passed once each, with unchanged before/after executable identity |
| Literal snippet regression | Two baseline failures through five and four assertions, plus a passing control; all three candidate cases passed without issues |
| Release | Actual Release build succeeded with coverage disabled; static Whisper verified across eight Mach-O files; ad-hoc Library Validation contract passed |

The ordinary unit result has 341 summary records and 339 unique identifiers because two parameterized identifiers appear twice. No failure issue message appears. These are decoded record and identifier counts, not a claim of 341 distinct executions or a retained console aggregate. The three unchanged correction regression whole files and shared fixture still match their known-red `4b50179d` source.

The six initial native cases cover TextEdit selection replacement with exact surrounding Unicode, drift refusal, Safari textarea selection, Local CLI writing-action failure handling, startup ownership after cancellation, and profile context eligibility. `native-six-results.json`, the raw native test log and result receipt establish those named test boundaries. They do not prove physical keyboard input or broad ASR/model quality.

The retained Release make log is 4,863,549 bytes, SHA-256 `bb1689ce52b91363b0f9dfb28157a0aefe24a0da54c77e36432ae62bcdaebbbf`. It shows `xcodebuild -configuration Release`, `ENABLE_CODE_COVERAGE=NO`, `BUILD SUCCEEDED`, static Whisper verification across eight Mach-O files, and the ad-hoc Library Validation contract for `MediaRemoteAdapter`. The duplicate make-log member in the artifact has identical bytes; this checkpoint retains one copy.

The artifact records inner app ZIP SHA-256 `e4f31cfa5dca2cd9c0ba130dc0d80c53f00d5ba05200e496f3784cc577cc34b6` and the same tested source SHA after packaging. The exact workflow source and successful Release step also establish completion of the post-make canonical-lock, bundle-identity, strict deep-signature, static Whisper, Library Validation and coverage-instrumentation checks. Their post-make stdout was not separately retained. This is CI packaging verification, not an independent reinspection of the packaged binary. No app archive was downloaded by this audit, and no notarization, publication or installed-app runtime acceptance is claimed.

`unit-results.json` retains the selected concrete unit records, xcresult member paths and decoded summary hashes. The complete decoded unit result remains at `/data/rjt-writing-check-01a17bef/40655003105/unit-details/details.json`, 4,899,023 bytes, SHA-256 `14bfee37f3ccf9606b59556889201c5126df9b818cf78e69e67620e4502ca781`. The six-case decoded native JSON has 4,281 bytes and SHA-256 `165d31b6e623576e27315bb579f7fb8356af66fe466901865ec2aa257566791b`. The broad owner fetched the workflow ZIP once. This audit used that existing ZIP and decoded data, with no archive or GitHub log fetch.

`source-preflight.json` records the 32 selected source hashes, Core registry and full package pins at this tested head. They are byte-identical to the [preceding retained whole-source snapshot](../../history-correction-full-40639673814/unit-failure-checkpoint/README.md), which this checkpoint references instead of duplicating. This is a selected source comparison, not a claim that every application or verification source remained unchanged.

`raw/` retains the current Core, package, dependency, mode/head, initial native, literal-regression and Release records. Its environment contract reports Xcode 26.6 build 17F113, macOS 26.6.2 build 25G83 and arm64. Run `python3 audit.py` in this repository to verify these retained records and their source cross-links.
