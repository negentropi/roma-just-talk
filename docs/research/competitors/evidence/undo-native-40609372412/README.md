Native Undo retry 40609372412 — failed fixture document identity

Exact head `02799617a8f13d2fa85abac02f9827cd1095fc94`; reused CI ref ends `794fa259`. Actual xcresult: one failed case, zero passes/skips. Remaining five never ran. App/test compilation, signature and TCC preparation succeeded.

Before/forward TextEdit text matched exact UTF-16 and ranges. New cleanup diagnostics show one matching focused token window/application, but `ownedDocumentURLMatches=false`, actions empty, saved text unconfirmed. Termination and cleanup both refused before save/close/termination commands. No Undo restoration ran.

Retained AX document uses `/private/var`; the resource failure path uses `/var`. Source first accepts standardized URL equality, then compares raw absoluteString representations. This explains the ownership failure; the exact contemporaneous raw URL at the failed cleanup call was not recorded. Keep URL authority and compare typed identities.

No failure attachments/screenshots. Global source-after/identity-after absent due abort; process phase identity/TCC/host closure retained. No Safari, ASR/provider quality, physical-input or release proof.
