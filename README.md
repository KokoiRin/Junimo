# Junimo

Junimo is a narrow macOS notch shell backed by a Go local backend. The current
product slice keeps the top-center trigger and provides independent Focus and
Todo pages in one expandable shell.

## Active Boundary

- Swift owns the macOS shell: AppKit lifecycle, menu bar presence, top-center
  panel, hover expansion, local page selection, text focus, and SwiftUI rendering.
- Go owns product behavior: the Pomodoro state machine, Todo lifecycle,
  persistence, and HTTP API.
- Swift renders backend snapshots and sends typed intents. It should not own
  product state machines.

See [AGENTS.md](AGENTS.md) for the repository instructions and language boundary rules.

## Current Slice

- A transparent 420-point-wide top-center hover strip with separate focus and
  Codex capsules. Its height follows the current display's menu bar and never
  drops below 28 points.
- Hover expands the notch into a 560×320 panel with a left Focus/Todo navigation
  rail and a right page area. Page selection stays local to Swift because it has
  no product meaning.
- The Focus and Todo pages render independent snapshots from the Go backend.
- The collapsed panel shows the remaining Codex 5-hour usage window on its
  right side.
- Focus supports 15, 25, and 45 minute starts.
- Focus can pause, resume, reset, complete, and hand off to a 5 minute break.
- Break can complete or be skipped back to the next focus setup.
- Focus and break completion show a temporary macOS notification with sound.
- Todo supports create, inline rename, explicit complete/restore, delete, and a
  collapsed completed section. New tasks appear first and persist locally.
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

Completion is visible in the notch panel state. Go publishes a stable completion
event ID when a focus or break first reaches `completed`; Swift only deduplicates
that event ID before invoking macOS `osascript display notification`.

## Todo Behavior

Go is the sole owner of the ordered Todo list. Swift keeps only transient input
and rename drafts; a task becomes official only after Go saves and returns a new
snapshot. Completion requests carry the target state instead of a toggle, so a
retried request cannot accidentally reverse a task.

Todo data is stored at `~/Library/Application Support/Junimo/todos.json`. A
failed or malformed Todo store marks only Todo as unavailable; health checks,
Pomodoro, and Codex usage remain operational. Tests may override the path with
`JUNIMO_TODO_STORE_PATH`.

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

`scripts/test.sh` runs the Go behavior suite, Swift DTO and shell-state tests,
a real Swift-to-Go HTTP contract test, and an offscreen SwiftUI regression test
for the expanded panel shape.

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

Protocol version 4 snapshots carry a monotonically increasing `revision` so
Swift can ignore late responses. Pomodoro snapshots also keep the latest
Go-owned `completionEvent` with a stable numeric ID, and Todo snapshots carry an
availability status plus the complete ordered task list.

Current intents:

```json
{"type":"pomodoro.startFocus","durationSeconds":1500}
{"type":"pomodoro.pause"}
{"type":"pomodoro.resume"}
{"type":"pomodoro.reset"}
{"type":"pomodoro.startBreak"}
{"type":"pomodoro.skipBreak"}
{"type":"todo.create","title":"Write the release notes"}
{"type":"todo.rename","id":"<stable-id>","title":"Update the release notes"}
{"type":"todo.setCompletion","id":"<stable-id>","completed":true}
{"type":"todo.delete","id":"<stable-id>"}
```

## Codex Usage

The Go backend queries the local Codex app-server in the background and caches
`account/rateLimits/read`. Requests to `/state` never wait for that external
query. The collapsed shell shows the primary 5-hour window when available and
an explicit unavailable state otherwise; the backend keeps the secondary
window in its snapshot for compatibility.

Junimo discovers `codex` from `PATH` and common user install locations. Set
`JUNIMO_CODEX_EXECUTABLE` to override the executable path.
