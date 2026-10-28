# RJT Mac feature PR readiness

[PR #30](https://github.com/negentropi/roma-just-talk/pull/30) contains the Mac app changes, focused Core/app/UI tests, user guides and automatic Mac/iOS checks. It adds snippets, Translate/Edit/Draft actions, cleanup profiles and styles, approved corrections, and guarded Undo Last Writing Edit.

The feature diff is separated from investigation-only workflows, drivers, historical inputs and research logs. Those remain in the [immutable verification checkpoint](https://github.com/negentropi/roma-just-talk/tree/69f9a2a3801b97d910520942a86ddb5c675ca94d) and on `codex/rjt-pr30-verification-20261028`. The [35-file input manifest](https://github.com/negentropi/roma-just-talk/blob/69f9a2a3801b97d910520942a86ddb5c675ca94d/docs/research/competitors/fixtures/historical-inputs-manifest.json) records exact captured bytes and their consumers. Consumers and inputs move together; the feature PR does not retain scripts with missing inputs.

## Source and review

The task was replayed onto default-branch commit `bf9ed37c19f6f381a0bde485da254dbeafb6234f`. Earlier updater work, YZU competition documents, hands-free Double Shift and the separate synthetic-key fix belong to other tasks and are excluded. The default branch's Codemagic configuration and changelog entry remain.

The final product changes were approved in three rounds by the same GPT-6.1 Sol reviewer selected at Medium effort, at source `2b165a5c960817f2b1ea4d5683c8f64e2109de3b`. The [review ledger](full-stop-sol-loop.json) records resolved findings, the accepted literal-output policy and runtime limits. Actual Claude Opus 5.5 authored the snippet UI mutation change. Usage for Sol was not exposed.

Projection keeps every product, resource, project, dependency and compiled-test path unchanged from that reviewed source. Only the complete investigation dependency closure is removed from this diff; retained documentation links point to the archive. Independent path, Git mode and blob comparisons are required before publication. Source approval does not certify an unseen projected commit or its CI.

## Verification boundaries

Automatic Mac and iOS checks execute the actual feature PR revision. Hosted `macos-26` jobs use independent workflow/ref queues and an installed Xcode 26 with the required Metal toolchain. Existing build/test assertions remain; the complete Mac job has a bounded 120-minute budget. Locale-stable model hashes and capture-readiness fixture fixes retain their original checks.

Extended UI, native Undo, dictation and matched-regression gates run on a verification branch descended from the feature PR revision. Their receipts retain the actual verification SHA. The supplied immutable `product_ref` must be an ancestor with identical product, resources, project/configuration, dependency and compiled-test trees. Normal-app/UI compiler inputs must also map to that feature source before attributing extended coverage to it. A shared package lock alone is insufficient. A verification-branch run is never labelled as an exact PR-head run.

Matched snippet-pipeline verification uses snippets-only commit `b4df0b236592fe701e45b249856a4b731e96b104`, before writing-action integration. Its project declarations match the feature composition. Review regressions separately compare known-bad `c1f3bb69356aed9abce01c43a4432c894b89c838` with the current reset function, snippet mutation helper and Paste Last service under unchanged oracles.

The [original evidence archive](https://github.com/negentropi/roma-just-talk/tree/99d0ebba40cfcd0f04a1536b4118cabe3a96a075/docs/research/competitors/evidence) retains earlier source-specific results. They establish only their documented revisions and boundaries. Read the current PR description and check results for final execution status.

Physical input, universal editor support, CloudKit synchronization and backup-conflict dialog interaction remain outside the retained runtime proof. Full-stop requires a ready, open PR and never authorizes merging or release publication.
