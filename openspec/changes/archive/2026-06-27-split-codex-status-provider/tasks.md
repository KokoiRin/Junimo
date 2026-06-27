# Tasks

- [x] 1. Add a fake-backed test for the monitor service boundary proving snapshot refresh and realtime findings are delivered through a typed sink.
- [x] 2. Introduce `CodexMonitorEventSink` / monitor service while preserving current bridge behavior.
- [x] 3. Split Codex adapter contracts, process runner, app-server client, realtime streams, snapshot parser, realtime parser, and provider into separate Swift files.
- [x] 4. Update architecture / Codex integration docs and `chowa/opportunities.md` to reflect the new Codex adapter boundary.
- [x] 5. Run `scripts/test.sh`, `scripts/build.sh`, `openspec validate --all --strict`, `git diff --check`, and `scripts/verify_ci.sh`.
- [x] 6. Archive the OpenSpec change after completion checks pass.
