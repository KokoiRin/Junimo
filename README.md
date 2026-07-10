# Junimo

Junimo is a narrow macOS notch shell backed by a Go local backend. The current
product slice keeps the top-center trigger and implements one Pomodoro timer
flow.

## Active Boundary

- Swift owns the macOS shell: AppKit lifecycle, menu bar presence, top-center
  non-activating panel, hover expansion, and SwiftUI rendering.
- Go owns product behavior: the Pomodoro state machine and HTTP API.
- Swift renders backend snapshots and sends typed intents. It should not own
  product state machines.

See [AGENTS.md](AGENTS.md) for the repository instructions and language boundary rules.

## Current Slice

- A transparent 420-point-wide top-center hover strip with separate focus and
  Codex capsules. Its height follows the current display's menu bar and never
  drops below 28 points.
- Hover expands the notch panel.
- The expanded panel renders Pomodoro state from the Go backend.
- The collapsed panel shows the remaining Codex 5-hour usage window on its
  right side.
- Focus supports 15, 25, and 45 minute starts.
- Focus can pause, resume, reset, complete, and hand off to a 5 minute break.
- Break can complete or be skipped back to the next focus setup.
- The app bundle includes both `Junimo` and `junimo-backend`.
- Legacy Swift/C++ feature code has been removed from the active tree.

## Pomodoro Behavior

The backend owns the Pomodoro state machine. Swift only renders snapshots and
sends intents.

```text
focus idle -> focus running -> focus paused -> focus running
focus running -> focus completed -> break running -> break completed
break running -> focus idle
```

Completion is visible in the notch panel state. Native system notifications are
not part of this slice.

## Build And Test

Run the local validation harness:

```bash
scripts/verify_ci.sh
```

Useful narrower commands:

```bash
scripts/test.sh
scripts/build_app.sh
scripts/run.sh
```

The smoke test build writes:

```text
.build/direct/junimo-backend
.build/direct/JunimoCoreSmokeTests
```

The app bundle is written to:

```text
.build/app/Junimo.app
```

Local ad-hoc app signing is best-effort because macOS may attach non-removable
file-provider xattrs inside synced folders.

## Backend API

The Go backend listens on `127.0.0.1:${JUNIMO_BACKEND_PORT:-44832}`.

```text
GET  /health
GET  /state
POST /intent
```

Current intents:

```json
{"type":"pomodoro.startFocus","durationSeconds":1500}
{"type":"pomodoro.pause"}
{"type":"pomodoro.resume"}
{"type":"pomodoro.reset"}
{"type":"pomodoro.startBreak"}
{"type":"pomodoro.skipBreak"}
```

## Codex Usage

The Go backend queries the local Codex app-server in the background and caches
`account/rateLimits/read`. Requests to `/state` never wait for that external
query. The collapsed shell shows the primary 5-hour window when available and
an explicit unavailable state otherwise; the backend keeps the secondary
window in its snapshot for compatibility.

Junimo discovers `codex` from `PATH` and common user install locations. Set
`JUNIMO_CODEX_EXECUTABLE` to override the executable path.
