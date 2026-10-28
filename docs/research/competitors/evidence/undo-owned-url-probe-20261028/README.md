# Owned URL representation probe

Fixture-only regression: `scopedURL` accepted the owned file using typed URL equality, then emitted the AX URL's `/private/var` representation. Cleanup compared that string with the resource's `/var` representation and refused before save, termination or Undo. Actual native evidence: [40609372412](../undo-native-40609372412/verification.json).

The candidate emits `resource.absoluteString` only after the same ownership comparison succeeds. Foreign file URLs remain redacted. No process, token, window or focus guard changes.

`old.swift` and `new.swift` contain the extracted method body. Only the signature and raw AX getter are replaced with a supplied value; `source-extraction.json` retains original/adapted hashes. The JSON files are actual stdout; exit codes are retained in that metadata. One existing owned temporary file supplies the same `/var` versus `/private/var` alias boundary as the native fixture. Old: exit 1, alias case fails, four controls pass. Candidate: exit 0, all five pass. Controls: exact resource, foreign file, non-file URL, unavailable value.

The initial probe supplied the verbatim remote paths on the local Mac, where the remote file tree did not exist. Both versions failed before the return expression because typed identity was false. That environment was invalid for regression proof. The accepted probe creates its own existing file and removes only that file and its temporary directory afterward.

Reproduce on macOS with `python3 reproduce.py`. Uses real Foundation; no app launch, AX operation, clipboard, native Undo, or process termination. Independent source review, Swift parse and diff checks passed. Native Undo acceptance still requires a fresh remote run.
