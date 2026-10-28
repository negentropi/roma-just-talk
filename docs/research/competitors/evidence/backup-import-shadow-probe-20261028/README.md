# Backup import member lookup probe

The actual app compile reported `cannot reference invalid declaration rows` inside the commit closure. This small Swift reproducer preserves the outer local, nested closure and same-named member call.

The existing `/usr/bin/swiftc -typecheck` observations are retained here. `old.swift` exits 1 with that same diagnostic; `new.swift` exits 0 after qualifying the member as `self.rows`. The source files differ only by `self.`. Combined captured stdout/stderr is in `old.log` and `new.log`; `receipt.json` records exits and SHA-256 hashes.

This is a compiler name-resolution check, not an app build, unit test, native interaction or persistence result. No binaries retained.
