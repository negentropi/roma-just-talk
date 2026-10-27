Run 40587701682 tested `ebf629b4cf109f7a36109ccac7b20ac70f9f48ab`. Six-case gate **failed**: four original cases passed once; the two new polish cases failed before their feature assertions. No six-case acceptance claim.

- Known-bad `bdd608cf` failed its one selected case at the intended foreground-control assertion, line 621. Candidate None/Custom case passed, including persistence and five shared native sheets.
- Style case failed while creating its literal snippet fixture. Declared input has 24 Swift characters; the recording shows 26. Exact resulting editor bytes were not captured. Keyboard CRLF handling is a hypothesis, not an observed byte trace.
- History case found exactly one seeded legacy row, then failed its nested expansion-ID lookup. The recording shows a normal collapsed row. No History AX hierarchy was retained; global expansion-ID availability remains unproved.
- Native seed and read-only verification each passed once, using distinct closed app hosts and the real normal-store factory. Four History rows, all 20 fields, and both library sentinels matched their declared expectations before and after UI. This proves synthetic store inputs and persistence, not ASR creation or completed History rendering checks.

`audit.json` records exact outcomes, limits and archive identity. `raw/` retains selected original receipts/logs. `shortcut-censuses.json` contains all 27 typed observations; each case restored its initial census, including a nonempty shortcut Data value. `screenshots/manifest.json` maps 17 original PNGs to test names and hashes. The two separately named failure frames derive from the actual recordings; their video hashes and offsets are in `audit.json`.

The single full artifact remains on remote `/data/rjt-writing-check-01a17bef/40587701682/evidence.zip`: 233,712,334 bytes, SHA-256 `b532748ad4c10fbaae7b3bd5dbdbe63dd4edc165752663848ee18c87b3a8d036`; all 4,179 ZIP members passed CRC verification. No full archive was downloaded locally. The failed Actions log was fetched once.

Approved follow-up changes test helpers only: owned native paste plus exact code-unit readback, and one exact global History expansion ID with uniqueness/row-frame assertions and retained AX diagnostics. Their runtime outcome is separate from this failed run. Future eight-case correction work is also separate.
