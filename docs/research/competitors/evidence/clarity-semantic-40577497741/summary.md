# First Clarity semantic attempts

All 27 actual `performClarity` calls completed through the remotely built probe at source `18552122392a0d161969074b1ff2361d1a9a5517`. None returned a decoded result. Every CLI execution exited 1 with the same raw output, `Failed to authenticate: OAuth session expired and could not be refreshed`. No semantic grading or retry was performed.

Fresh Mac signature, artifact, input and runner checks passed. Bare auth status immediately before execution reported logged-in true, API-key authentication and first-party provider. That status did not prove authentication for the isolated print configuration. The cause of that discrepancy remains unverified. Model selection stayed at the CLI default; the served model is unavailable.

The exact packaged runner retained all 27 first attempts, raw stdout/stderr/stdin, request metadata and separate generation inputs. Its completeness verdict passed. That verdict describes retained observations, including failures, and does not claim semantic success. Exact request/capture/code-unit, isolated working-directory, unchanged executable and empty persistent-preference checks passed.

Rubric bytes and authentication files were not copied. The only retained authentication status fields are loggedIn, authMethod and apiProvider. No successful authenticated model output, app pipeline, profile activation, microphone, editor delivery or UI behavior is established by this run.

The [build evidence](../clarity-semantic-build-40577497741/summary.md) identifies the actual service sources, dependencies, binary and signature. `observations/` retains original run receipts and raw captures; `generation-inputs/` is a post-run artifact copy that was never supplied to a model as earlier context.
