# Native Undo evidence identity checks

The original seven-case driver at `0b60c5e62` accepts five invalid receipt counterexamples. The candidate rejects each one and retains the valid controls. [Receipt](receipt.json).

The counterexamples change a negative-case stage PID, a later stage token, a startup PID, two startup bundles while preserving their census, and an unobserved fixture UUID. The candidate binds all three negative stages to the same editor and each observed editor token to its startup PID and bundle. It also validates every startup UUID.

Run from the repository root:

```sh
python3 docs/research/competitors/evidence/undo-native-driver-identity/verify.py --output /tmp/undo-native-driver-identity.json
```

The proof executes the actual old and candidate pure validators and `phase_result` on isolated JSON files. Only the OS host-closure and TCC boundaries are inert stubs. No app builds or launches, Accessibility operations, clipboard reads or provider calls occur. The five old false passes and five candidate rejections are verification regressions, not native product results. The already-running seven-case Mac artifact remains bound to its original driver; its runtime audit can apply these stronger predicates offline without changing that artifact.
