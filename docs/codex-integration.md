# Codex Status Integration

Junimo should treat Codex state as adapter-owned platform state. The portable
C++ core can keep generic session history, but live Codex quota, thread, and
completion signals should enter through Swift-side adapters because they depend
on local processes, authentication, and Codex protocol versions.

## Authoritative Sources

- Codex thread model: a thread is a session, and it is running while Codex is
  actively working on it. Threads can be local or cloud-hosted.
- Codex app-server: local JSON-RPC interface for rich clients. It provides
  authentication, conversation history, approvals, and streamed agent events.
- Codex CLI cloud list: `codex cloud list --json` returns recent cloud tasks
  with `id`, `url`, `title`, `status`, `updated_at`, environment fields,
  summary, review flag, and attempt count.
- Codex CLI exec JSON: `codex exec --json` emits JSONL events including
  `thread.started`, `turn.started`, `turn.completed`, `turn.failed`, `item.*`,
  and `error`.
- Enterprise Analytics API: reports daily or weekly workspace usage, including
  threads, turns, credits, and token fields. It can lag and requires enterprise
  analytics permission, so it is a reporting source rather than a local live
  quota meter.

## Quota

Best live path: connect to `codex app-server` and call
`account/rateLimits/read`. The generated schema for Codex CLI 0.137.0 exposes a
`rateLimits` snapshot plus `rateLimitsByLimitId`, with plan type, credits,
primary and secondary windows, reset timestamps, and used percentages.

Fallback paths:

- `account/rateLimitsUpdated` notifications can update the displayed quota while
  a client remains connected.
- Enterprise Analytics can show historical daily or weekly usage, but not a
  precise local "5-hour remaining" meter for every user.
- If app-server is not connected, Junimo should show "Needs setup" instead of
  inventing remaining quota values.

## Running Conversations

Best live path: connect to `codex app-server`, call `thread/list`, and subscribe
to thread and turn notifications. The generated schema exposes
`ThreadStatusChangedNotification` with `active`, `idle`, `systemError`, and
`notLoaded` states. Active threads can include flags such as waiting on approval
or user input.

Junimo normalizes these source states into a smaller lifecycle model:

- `running`: Codex is actively executing.
- `waiting`: Codex is active but waiting on user input, approval, or another
  blocking flag.
- `open`: a non-archived conversation exists, but the current source did not
  load a precise running state. App-server `notLoaded`, `idle`, and unknown
  non-terminal local statuses land here.
- `completed` / `failed`: only explicit terminal events or explicit terminal
  source statuses.

`notLoaded` is never treated as completed, and snapshot absence alone never
creates a completion alert.

Useful local diagnostics:

- `codex doctor --json` reports Codex version, auth mode, app-server daemon
  state, thread inventory consistency, and local state paths.
- It is a diagnostic snapshot, not the main live event stream.

Cloud task path: call `codex cloud list --json --limit N` and map returned task
statuses into Junimo thread summaries.

## Completion Alerts

For Junimo-launched local runs, prefer `codex exec --json` and watch for
`turn.completed` or `turn.failed`. For app-server-backed runs, listen for
`turn/completed`, `thread/statusChanged`, and `thread/closed`.

Junimo now has a `CodexMonitorSnapshot` and `updateCodexThread(...)` entry
point. When a known Codex thread transitions from `running` or `waiting` into
`completed` or `failed`, or when an `open` thread receives an explicit terminal
event, `TaskCoordinator` creates a `NotificationRequest` and records a recent
activity entry. It also creates a persistent Codex review item that stays
visible in the island until the user acknowledges it.

## Current Implementation

- `CodexFeature` owns quota source status, known Codex threads, review
  attention, collapsed status priority, and agent projection.
- `TaskCoordinator` remains a compatibility facade for SwiftUI. It delegates
  Codex state changes to `CodexFeature` and consumes notification/activity
  effects.
- `CodexThreadLifecycleReducer` owns lifecycle ordering and counts. It computes
  active, open, and terminal counts from the full normalized thread set before
  the visible island list is limited to eight entries.
- `CodexAdapterContracts` defines typed provider, stream, event, command, and
  app-server query boundaries.
- `CodexProcessRunner` owns one-shot `codex` process execution.
- `CodexCLIStatusProvider` runs `codex doctor --json` and
  `codex cloud list --json --limit 20`, then maps the output into
  `CodexMonitorSnapshot`.
- `ProcessCodexAppServerClient` starts `codex app-server --stdio`, performs the
  JSON-RPC initialize handshake, then reads `account/rateLimits/read` and
  `thread/list` before terminating the short-lived process.
- `ProcessCodexAppServerEventStream` starts `codex app-server --stdio`, performs
  the initialize handshake, and parses JSON-RPC notifications such as
  `account/rateLimitsUpdated`, `thread/statusChanged`, `turn/completed`, and
  failure events into realtime monitor events.
- `ProcessCodexExecEventStream` wraps `codex exec --json` JSONL streams when an
  app-owned adapter needs to observe them, mapping `thread.started`,
  `turn.started`, `turn.completed`, `turn.failed`, and `error` events into the
  same realtime monitor path.
- `CodexStatusParser` parses doctor, cloud list, app-server quota, and
  app-server thread-list payloads into typed monitor snapshots.
- `CodexRealtimeEventParser` parses app-server notifications and exec JSONL
  lines into typed `CodexRealtimeEvent` values.
- `CodexMonitorService` connects provider snapshots and realtime streams to a
  typed `CodexMonitorEventSink`. `CodexMonitorRefreshBridge` is now the thin app
  shell wrapper around that service.
- Pressing the Codex action no longer creates a placeholder running thread.
  Running/waiting/open/completed/failed state must come from adapter snapshots
  or realtime events.
- `CodexFeature.updateThread(...)` and `CodexFeature.applyRealtimeEvent(...)`
  are the product-state ingestion points for app-server, cloud-list, and
  exec-JSON adapters.
- The expanded island UI shows quota source, active/known thread count, and
  whether a Codex completion alert is pending. When a review item is pending,
  the collapsed island's right-side status pill shows `Codex done` or
  `Codex failed`; the collapsed island renders a persistent animated attention
  cue, and the collapsed status pill and badge can acknowledge the latest
  result directly. Without a review or active thread, remaining open
  conversations show as `Codex open N` before the UI falls back to quota text.
  The expanded island also shows the latest result with an acknowledgement
  control.

## Next Adapter Work

1. Move from stdio app-server streaming to a reusable `unix://` connection if
   the local Codex app-server exposes one for rich clients.
2. Keep command execution off the SwiftUI render path. Refresh in background and
   publish snapshots onto the main actor.
