## 1. Tests First

- [x] 1.1 Add parser/reducer coverage for app-server `notLoaded`, `idle`, `active`, waiting flags, and terminal statuses.
- [x] 1.2 Add coordinator regression coverage: one thread completes while another open thread remains, collapsed status shows open work instead of quota.
- [x] 1.3 Add coordinator regression coverage: a previously active thread missing from a later snapshot does not create a completion review.
- [x] 1.4 Add ordering coverage: active/open threads are preserved before UI list truncation.

## 2. Lifecycle Model

- [x] 2.1 Introduce a Codex thread lifecycle reducer or equivalent module in `JunimoCore`.
- [x] 2.2 Preserve raw app-server `notLoaded` / unknown statuses instead of collapsing them to idle.
- [x] 2.3 Move terminal-transition detection out of ad hoc snapshot absence logic.
- [x] 2.4 Compute active/open/terminal counts from the full normalized lifecycle set before UI truncation.

## 3. Coordinator And UI

- [x] 3.1 Update `TaskCoordinator` to apply reducer outputs and create review items only for explicit terminal transitions.
- [x] 3.2 Update collapsed status priority to include open work between active/waiting and quota.
- [x] 3.3 Update launch health diagnostics to expose open and terminal counts.

## 4. Docs And Verification

- [x] 4.1 Update `docs/codex-integration.md` with lifecycle source-of-truth and `open` semantics.
- [x] 4.2 Update `docs/progress.md` and Chowa opportunity status after implementation.
- [x] 4.3 Run `scripts/test.sh`, `scripts/verify.sh`, and `openspec validate --all --strict`.
