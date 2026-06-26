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
`completed` or `failed`, `TaskCoordinator` creates a `NotificationRequest` and
records a recent activity entry.

## Current Implementation

- `TaskCoordinator.codexMonitor` stores quota source status, known Codex
  threads, and integration findings.
- `CodexCLIStatusProvider` runs `codex doctor --json` and
  `codex cloud list --json --limit 20`, then maps the output into
  `CodexMonitorSnapshot`.
- `ProcessCodexAppServerClient` starts `codex app-server --stdio`, performs the
  JSON-RPC initialize handshake, then reads `account/rateLimits/read` and
  `thread/list` before terminating the short-lived process.
- `CodexStatusParser.usageSnapshot(fromAppServerRateLimitsJSON:)` parses the
  app-server `account/rateLimits/read` response shape into the same quota model.
- Pressing the Codex action records a Junimo-known local Codex thread as
  running.
- `updateCodexThread(...)` is the event ingestion point for future app-server,
  cloud-list, and exec-JSON adapters.
- `CodexMonitorRefreshBridge` refreshes the CLI snapshot in the background and
  publishes it through `TaskCoordinator`.
- The expanded island UI shows quota source, active/known thread count, and
  whether a Codex completion alert is pending.

## Next Adapter Work

1. Replace the short-lived `codex app-server --stdio` probe with a reusable
   app-server session or `unix://` connection so Junimo does not respawn the
   server for every refresh.
2. Subscribe to app-server notifications such as `thread/statusChanged`,
   `turn/completed`, and `account/rateLimitsUpdated`.
3. Wrap `codex exec --json` when Junimo starts a local Codex task, streaming
   JSONL into `updateCodexThread(...)`.
4. Keep command execution off the SwiftUI render path. Refresh in background and
   publish snapshots onto the main actor.
