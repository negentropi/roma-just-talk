# Recording finalizer run 40588406953

[Exact run](https://github.com/negentropi/roma-just-talk/actions/runs/40588406953), source `650fab297aa0fcc7f3c9a6549583034b32942850`, ref `ci/rjt-recording-finalizer-01a17bef`.

Invalid signature preflight. Both native app builds succeeded and both static Whisper checks verified 18 Mach-O files. Neither selected test started; no intended assertion failure, context-generation value or matched red/green result was observed.

The driver used the release/local signature verifier for an Xcode ad-hoc build-for-testing host. Both resolved build settings already had `ENABLE_HARDENED_RUNTIME=YES`, `ENABLE_DEBUG_DYLIB=NO` and `ENABLE_PREVIEWS=NO`. Both actual build logs explicitly report that Xcode disabled Hardened Runtime for ad-hoc signing. The verifier rejected that host before TCC provisioning, isolated launch configuration, enumeration or test execution.

`audit.json` independently checks the exact Engine/oracle/guard-fixture hashes, the sole Engine source difference, 41 matching clean package revisions/tree identities, identical static Whisper bytes, build success, and restoration of the task-owned baseline checkout. `failed.log` was fetched once; compact observations and the small native log artifact were each fetched once. The original release verifier remains unchanged.

Follow-up source preparation adds a separate read-only ad-hoc test-host verifier. It checks the actual main signature, strict deep bundle validation, and disabled Library Validation when bundle-relative code requires it. It retains raw flags and makes no signing change. Its mocked contracts do not establish actual native signature or launch acceptance.

`oracle-bridge.json` documents a later committed common-oracle update: one unselected Optional `.none` assertion now names `VoiceInkDictationProfile.none`. The two selected guard-test bodies are byte-identical. No native regression result is claimed for the updated oracle.
