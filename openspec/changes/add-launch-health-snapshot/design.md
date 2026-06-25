## Context

The app can be launched as `.app`, but screenshots from this environment currently show a black screen or lock screen. A process check proves the executable is running, but not that the panel and coordinator were initialized. A small health snapshot provides stronger evidence.

## Goals / Non-Goals

**Goals:**
- Write a JSON health file after panel creation.
- Keep the file local under `/tmp` by default.
- Include enough state to prove AppKit and C++ core-backed coordinator initialization.
- Validate the JSON from shell scripts.

**Non-Goals:**
- Do not add telemetry or external upload.
- Do not expose a network health endpoint.
- Do not persist user preferences in this health file.

## Decisions

1. **Health file path**
   - Default: `/tmp/junimo-health.json`.
   - Override through `JUNIMO_HEALTH_PATH` for tests.

2. **Simple JSON writer**
   - Use `JSONSerialization` and Foundation values.
   - Avoid introducing Codable model churn for one diagnostic snapshot.

3. **Panel controller exposes diagnostics**
   - `NotchPanelController` returns panel frame/level/visibility.
   - `LaunchHealthReporter` combines panel diagnostics with coordinator state.

## Risks / Trade-offs

- **Health file is not visual proof** -> It complements process checks and tests, but unlocked desktop screenshots are still needed for true hover/click visual QA.
- **Local temp file can be stale** -> Launch script removes the file before starting and checks modification/content after launch.
