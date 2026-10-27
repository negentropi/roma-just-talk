# Ollama Writing Action model identity

Prerequisite for Clarity provider capture; independent of the Custom/None native gate on `830d45210816a36c2db70b09d1329a0ef8b7ddf6`. The [source investigation and exact SDK contract](ollama-snapshot-regression-design.md) describe the suspected mismatch. Source alone does not establish its actual request behavior.

- [x] Read Poteto Principles in full; apply bounded ownership, Fix Root Causes, Model the Domain and Prove It Works.
- [x] Blocking first step: inspect both model-selection owners and the actual pinned SDK. Preserve the runtime lowercase preference and its named `llama2` fallback.
- [x] Independent workstreams: one backend owner owns the two actual service files; one proof owner owns a new narrow real-transport driver/workflow. Parent owns integration, review, documentation and commits.
- [x] Shared mutable state: no UI/Core/schema changes; no temporary global provider/model mutation to execute a captured request. Isolated probe identities select Local CLI before service initialization, then use Ollama's credential-free route.
- [x] Smallest safe decomposition: one immutable endpoint/model configuration owned by the existing Ollama service; no new provider hierarchy, transport substitute, dependency or compatibility alias.
- [x] Source review the actual two-file backend diff. The request configuration is an immutable value; the existing generator owns request validation and error mapping. Proof-driver review remains pending.
- [ ] Same unchanged oracle against pinned `830d4521` and candidate: actual requests and successful decoded responses must precede the two precise old metadata failures. The coherent stored-model control must pass on both.
- [ ] Candidate preserves selected model/endpoint across later preference edits; new snapshot uses the new selection. Capture and execution do not persist unexpected preference writes.
- [ ] Run full relevant Mac gate after integration; shared Core and UI are unchanged by this provider unit. Keep the earlier None UI/runtime evidence bound to its own exact revision.
- [ ] Atomic commits with explicit owned paths, user-facing changelog and actual proof receipts. Created disposable CI refs only; no normal branch push or release.

The proof uses two owned loopback HTTP listeners, actual app services and pinned LLMkit. It verifies request routing, body, result identity and preference isolation. Synthetic responses do not establish real Ollama quality, server-version compatibility, microphone behavior or editor insertion. Timeout/cancellation behavior remains separate unless this patch changes it.
