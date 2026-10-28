# Dictionary isolation literal control

The original test fixture was already valid. Its source SHA-256 was `999bb7ca2aa276a257710212d09288fd15ddac1ea3a3a484ee1a53f8ec99a534`. The apparent doubled escapes came from serialized display, not the source bytes.

`probe.swift` contains the exact extracted `editedText`, `original` and `newer` declarations. Actual Foundation execution returned canonical String equality for the two spellings while their UTF-16 sequences differed: decomposed `[101, 769]` versus composed `[233]`. The edited text contained CRLF, decomposed text and one literal backslash before `Temp`. The hypothetical double-escaped spelling was canonically unequal, but it was not the existing fixture.

`observation.json` is captured stdout; `receipt.json` records its hashes and exit. The new test precondition makes the valid canonical-equality/code-unit-difference boundary explicit before either scenario. This strengthens the oracle. It is not a fixture repair, old-product failure, app-unit pass or native interaction result. No binaries retained.
