## Context

The app currently records activities and can search commands, but activity entries are event logs rather than durable execution state. Real agents and local commands will need a stable model for queued/running/succeeded/failed sessions.

## Goals / Non-Goals

**Goals:**
- Model sessions in the C++23 core.
- Keep the first UI compact and bounded to recent sessions.
- Record mock sessions for existing action and Pomodoro flows.
- Preserve adapter boundaries and avoid direct shell execution.

**Non-Goals:**
- Do not add background workers or async process management yet.
- Do not persist sessions to disk.
- Do not add cancellation/retry controls beyond Pomodoro cancel.

## Decisions

1. **Session status is explicit**
   - Status values: queued, running, succeeded, failed.
   - Agent actions remain running to represent active local agents.
   - project/tools actions complete immediately as mock successful sessions.
   - Pomodoro sessions are running when started.

2. **Bridge returns bounded snapshots**
   - C API returns up to 6 recent sessions.
   - Swift copies strings synchronously and publishes value models.

## Risks / Trade-offs

- **Sessions are currently in-memory only** -> acceptable for first scale-up; persistence can follow once the model is stable.
- **Mock statuses are simplistic** -> sufficient until real adapters can report lifecycle events.
