# Writing delivery/import comparison: invalid fixture setup

[Run 40597919426](https://github.com/negentropi/roma-just-talk/actions/runs/40597919426), exact `c5859b1f59997633fbd59d92565eb70c173c8392`, compiled and selected all three intended native cases. All three failed during fixture AIService initialization, before entering the operation. This is not reproduction of post-delivery cancellation or a pending import row. [Receipt](receipt.json).

The actual failures are the same compound requirement: `ai.selectedProvider == .localCLI && ai.isAPIKeyValid` evaluates false; `ai.apiKey.isEmpty` is not evaluated. The Audio fixture fails at line 519 and both Writing cases at line 127. The three-case run lasts 0.120 seconds, records exactly three setup issues and reaches zero allowed post-mutation assertions or controlled read-only save failures. The classifier correctly rejects this boundary; no product fix is established.

Historical receiver `c29ac2d7c6fa7690ea3bd0d5a38697b44a37d182` retains its full tracked production source except the exact captured-value session initializer bridge. The tracked Audio test source is explicitly replaced with the frozen common file, and the common Writing test file is added. Original source inventories, original Audio/session sources, exact bridge, complete test diff and after-run preservation remain retained. These are instrumentation exceptions, not unchanged historical tests.

The one observations archive is 636,865 bytes, SHA-256 `6308b8fcec41fe9eb722f1c5073f15eef8756ace502d1ae33e859bdaa99ee3ec`; all 50 members pass CRC. The single failed-log fetch is retained. The 94 MB native build/xcresult archive was not downloaded; its identity is GitHub metadata only. Signed-host, exact selection and unchanged app/test-identity receipts are retained, with their actual narrower scope.

The compound requirement does not reveal which provider/validity operand caused setup failure. Actual configuration readback is required before changing setup. The fixed-value oracles and product receivers were not changed as part of this audit. No physical editor, ASR, model-quality or Undo gesture proof.
