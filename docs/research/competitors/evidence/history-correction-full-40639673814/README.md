# Eight UI cases green, native post-verification permission preflight red

Normal full40639673814, exact3f62c6da2fd98361d48305c9c5e0d01bed980f82. All eight UI cases passed once, zero failures in1279.560s. This includes real correction preview/cancel/canonical edit/approval, Dictionary toggle/edit/delete/relaunch, History source deletion and deleted-source provenance/editor relaunch. Copy11 and StaticText21 are exact against independent seed and declared literals.

The final native host did not run. Its preflight found microphone authorization changed from2 before seed to0 before verify, with the same client and signing requirement. Accessibility remained2. App/native-test hashes and signature texts are byte-identical seed-before/after/verify-before. The driver queries permissions before seed, not after it, so the transition cannot be assigned to seed startup versus UI. Physical app/store closure after UI is verified; it does not prove hidden persisted fields.

Actual UI log shows XCTest implicitly clicking Don't Allow twice in the first case at16.15s and17.74s on a UserNotificationCenter dialog. Exact title/services were not retained. Source shows startup HAL pre-roll can activate input before dictation; runtime causality remains unproved. No permission check was relaxed or silently repaired.

Core/unit/package/native6/matched facts are retained independently under unit-failure-checkpoint. Release was skipped. No app package or publication claim.

All43 original PNGs were individually reviewed with matching hashes. One saved-state copy inconsistency is retained as visual red, with the later candidate fix separate. One520MB full artifact fetched remotely, SHA/all8665CRC verified; no duplicate screenshot ZIP or fullZIPlocal. Every source snapshot is pinned to3f62, not later permission-monitor work. Full gate remains unaccepted.
