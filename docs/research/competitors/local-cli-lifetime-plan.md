# Local CLI request lifetime prerequisite

Independent prerequisite for Clarity, before profile activation. No UI, schema, dependency or provider-selection changes. User-approved command templates still run through `/bin/zsh -lc`; existing stdin and prompt environment variables, settings persistence, output trimming, empty-output errors and nonzero-exit errors remain the legacy contract.

## Owning failure and change

At `aaaa286a`, `LocalCLIService` writes stdin synchronously before arming its timeout and waits for exit before draining stdout/stderr. A full pipe can block that lifetime. Task cancellation never reaches the process. These are source findings; the old native failure must still be reproduced by the matched gate.

`588fcdac` replaces that execution path with one per-call owner. Nonblocking input and both outputs run concurrently. The deadline starts before input. Launch, cancellation, timeout, signals, child reaping and one completion share a serial queue. POSIX spawning and same-owner `waitpid` keep the child unreaped until its owner decides whether to signal or reap; a Foundation `Process.isRunning` check followed by a separate PID kill would not provide that ownership.

Cancellation sends TERM, then bounded KILL if required, to the owned unreaped child. It makes no descendant, remote-model or server-work termination claim. The owner refuses a parent SIGCHLD disposition that auto-reaps or replaces normal ownership; it never changes global parent signal handling. Actual app-host compatibility remains required. Pipe writes suppress SIGPIPE per descriptor, and C-string inputs reject embedded NUL rather than silently truncating.

Immutable `RequestConfiguration` and raw `execute` prepare later Clarity use. Raw output stays literal; the existing `enhance` wrapper retains trimming and empty-output classification. The AI enhancement service still uses its existing snapshot/filter path, and the recording engine still needs its operation-owned provider task before cancellation can reach Clarity. This prerequisite does not claim that integration.

## Evidence and remaining gates

- [Small native owner probe](https://github.com/negentropi/roma-just-talk/blob/99d0ebba40cfcd0f04a1536b4118cabe3a96a075/docs/research/competitors/evidence/local-cli-owner-smoke/probe.receipt.json): actual owner body, real Core error enum, strict Swift 6 typecheck, large pipes, early exit and cancellation. Its local logging identity is supplied as a literal. It does not independently observe the canceled child's PID or establish public service/Core/app behavior.
- [Macro shapes](https://github.com/negentropi/roma-just-talk/blob/99d0ebba40cfcd0f04a1536b4118cabe3a96a075/docs/research/competitors/evidence/local-cli-owner-smoke/macro-shapes.receipt.json): actual throws/require expressions typecheck in Swift 5/6. Typed closures replace service bodies. This catches macro expansion errors, not real API or runtime errors.
- Matched remote gate: exact old/new production files, identical old-compatible public-API probe, shared real Core/NVIDIA source and existing 22-pin lock. Require the old cancellation failure at the named boundary, ordinary/unrelated controls green, complete natural fixture cleanup, and all candidate cases green. Candidate-only literal/snapshot calls are separate from regression proof.
- Actual app-host compilation and all ten new tests; unchanged existing writing-provider, native delivery, Core and relevant UI checks; final Release/package gate. Do not infer app-host SIGCHLD compatibility from the tiny standalone probe.

The remote oracle must retain signed identities, source/pins before and after, actual PID/PPID/executable observations, typed outcomes, bytes/hashes, deadlines and cleanup. Setup, zero execution, watchdog recovery or cleanup failure cannot count as a reproduced old bug or candidate success. No external provider, credentials, TCC or user foreground is needed for the narrow comparison.

## Accepted direct-service comparison

[Run 40569060351](https://github.com/negentropi/roma-just-talk/actions/runs/40569060351), exact `77d84bd1`, passed the matched gate. The old service failed the four intended pre-cancel/input/output/deadline boundaries; its survivor, exit-race and later-request controls passed. The candidate passed all six lifetime cases and all three separate literal/configuration cases. Its TERM-ignoring direct child exited and was reaped in 1.0483 seconds; the supported five-second timeout completed in 6.0571 seconds including escalation/reaping. Exact large stdin/stdout and completed stderr writes verified. The [independent receipt](https://github.com/negentropi/roma-just-talk/blob/99d0ebba40cfcd0f04a1536b4118cabe3a96a075/docs/research/competitors/evidence/local-cli-lifetime-40569060351/receipt.json) binds actual kernel identities, cleanup, unchanged sources, 22 pins, binaries and signatures.

The [earlier fixture run](https://github.com/negentropi/roma-just-talk/blob/99d0ebba40cfcd0f04a1536b4118cabe3a96a075/docs/research/competitors/evidence/local-cli-lifetime-40566195249/README.md) compiled all service targets but rejected process identity. Its mixed `ps` display columns were unsuitable for executable identity. The corrected observer uses kernel paths, canonical file device/inode, and separately retained parent/argument fields. Captured long/spaced path observations reproduce the old parser rejection. The first run remains invalid; it is not counted as a product regression.

This establishes actual direct-child service behavior. It does not prove descendants, external model quality, app/UI integration or newer Core changes. Full Mac run `40567596198` separately passed Core, units, six native cases and matched regressions at `919670ae`, then reported one profile UI failure; raw ten-test counts and that failure are under audit, and Release did not run.
