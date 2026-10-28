# Seven-case native fixture contract

The immutable diagnostic run [40615667402](../undo-native-40615667402/README.md) remains three TextEdit passes and three Safari failures before Undo. It observed composed AX readback for decomposed requested output. This next unit corrects the success fixtures and adds a negative acceptance boundary; it is not a production regression fix or a green result for the prior six-case run.

`LiveWritingEditor.open(_:passage:)` accepts an opt-in exact fixture passage. Its default `target e` plus U+0301 bytes remain unchanged. Retained `sourcePassage`, `sourceOriginal` and `sourceRange` drive file content, exact readiness, selection and diagnostics. The helper performs no normalization. All existing default callers keep their original source bytes.

The three positive Safari cases explicitly seed `target é` and request precomposed `é` outputs. Their forward and inverse full-text/range assertions remain exact UTF-16. Emoji, multiline replacement and independently seeded two-item clipboard data remain covered; clipboard payloads still include decomposed UTF-8 bytes. TextEdit's three native scenarios and its decomposed Unicode outputs are unchanged.

The seventh selector is `liveWritingUndoSafariRejectsNormalizedDecomposedOutput`. It uses the default decomposed source, requests literal `Unconfirmed e` plus U+0301 and ` 😀`, requires `attemptedUnconfirmed(replacementUnconfirmed)` after one forward attempt callback and zero confirmations, and checks the exact observed `Unconfirmed é 😀` full text with a caret one UTF-16 unit shorter. Controller Undo must return unavailable; the retained text/range/identity must remain exact. No retry or canonical-equivalence authority is introduced.

Its exact stages are `nfd-before`, `nfd-unconfirmed`, `undo-unavailable`. Common exact-text/range/route checks remain required. Only this explicit negative case permits latest forward confirmation count zero. `negativeAttemptCallbacksAfterUndo` counts the fixture's real forward callback; it does not expose or count arbitrary native AXPress operations. The unavailable controller result and unchanged retained snapshot establish the negative Undo boundary.

The driver requires one exclusive-process selector followed by six remaining selectors, all seven executed exactly once, valid signature/TCC/host closure/source receipts, and the exact per-case stage sets. Native execution and menu/shortcut proof remain pending until independently audited runs exist. Production source remains unchanged.
