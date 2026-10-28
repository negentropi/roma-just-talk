# Current English choice persists: 40617652407

[Hosted run](https://github.com/negentropi/roma-just-talk/actions/runs/40617652407), exact `2ebdfd1772e3f45f9fe1fe4e2787af7fbfc53ea2`, passed the real `LanguageSelectionView(.full)` component check with native exit 0. English was initially registered/effective but absent from both persistent-domain observations **after mounting**. Accessibility pressed the already checked English item once; both NS and CF persistent domains then contained `en`. [Receipt](receipt.json), [native observations](artifact/native/result.json).

| Stage | Persistent language | Fresh Light output |
| --- | --- | --- |
| Mounted, before choice | absent | `Um, send it tomorrow.` |
| Choose current English | `en` | `send it tomorrow.` |
| Choose Japanese | `ja` | `Um, send it tomorrow.` |
| Choose English again | `en` | `send it tomorrow.` |

The view is unchanged from the parent source. The test host uses the real unloaded multilingual `ggml-tiny` catalog model, public model-selection API and strongly retained real managers. The [Opus authorship receipt](../language-selection-probe-source/authorship-and-review.json) binds the test-only host. No engine, model weights, inference, provider or synthetic replacement picker is used. The private language setter is not instrumented; the persistent transition is the observed behavior.

The [audit](audit.py) verifies all 612 pinned source hashes, 605 unchanged/generated candidate files, 221 actual app Swift inputs excluding only the normal app entry, 41 actual package checkout revisions/trees, static dependency receipts, signed identity and three fresh signed TCC rows. The same mapped host PID 27718 exits and has no remaining executable mapping or process. Explicit coverage output remains outside the guarded source tree.

All seven screenshots were visually reviewed: [baseline](artifact/native/baseline.png), [current checked English](artifact/native/same-current-english-menu.png), [after current English](artifact/native/same-current-english-after.png), [Japanese control menu](artifact/native/changed-japanese-menu.png), [Japanese result](artifact/native/changed-japanese-after.png), [return-English menu](artifact/native/changed-english-menu.png), [English result](artifact/native/changed-english-after.png). The two changed-selection menu screenshots show the prior current item; their requested items lie outside the visible menu segment. Actual AX item/action receipts and final picker values establish those controls. This does not claim physical scrolling or clicking.

One downloaded observation archive: 4,644,568 bytes, SHA-256 `e164dba9844863e871ebba3d92fb0a2e30ebb77414371e6b6280fd06d0f3d7c7`; all 52 members pass CRC. The original ZIP and 8,869,424-byte runtime profile remain at `/data/rjt-writing-check-01a17bef/language-selection-40617652407/`. The other 51 members are retained under [artifact](artifact), with [member hashes](artifact-members.json). The separate build/native log artifact was not downloaded. The [first setup run](../language-selection-40616190134/README.md) was canceled after cache saving, before any accepted runtime result.

This proves the tested component's current-English selection and its explicit-language Light behavior on hosted macOS 26.6.2 / Xcode 26.6. It establishes no same-value Picker defect and requires no production UI change. Full Models-page composition, model usability, ASR, microphone, providers, physical input, all macOS versions and release behavior remain outside this check.
