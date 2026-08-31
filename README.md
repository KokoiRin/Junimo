# Junimo

Junimo is a lightweight macOS Codex companion. It lives around the built-in display notch, shows the remaining Codex usage window, makes completed Codex tasks audible, and opens a few frequent destinations without becoming another task manager.

## Current Product

- A transparent 420-point top-center hover strip that stays available across spaces.
- A collapsed Codex activity capsule and primary usage capsule.
- Hover expansion into a single 560×260 companion panel.
- A quick-launch row that starts with Codex and can be extended with personal websites or macOS applications.
- A user-editable JSON catalog that reloads immediately after the file is saved.
- Background Codex usage refresh without blocking `/state`.
- Recent local Codex thread scans through one long-lived app-server process.
- A stable completion event for each newly persisted successful Codex turn.
- One clickable Junimo completion banner with the distinctive `Hero` sound and task title per completion event; clicking it opens the matching Codex task without depending on system notification permission.
- A menu-bar item for showing or quitting Junimo.

## Active Boundary

- Swift owns the macOS shell: AppKit lifecycle, menu bar, notch placement, hover expansion, SwiftUI rendering, sound delivery, and `NSWorkspace` launch actions.
- Go owns Codex adapters and product facts: usage caching, recent-thread monitoring, completion detection, stable event publication, and the HTTP state API.
- Swift renders Go snapshots; it does not query Codex or infer task completion.
- Go does not know AppKit layout, notification presentation, or application launching.

## Completion Detection

Junimo starts an independent Codex app-server connection and polls recent interactive threads. The first successful scan establishes a baseline, so old completed tasks do not generate startup noise. Later `completed` turns produce events keyed by their stable Codex turn IDs; failed and interrupted turns are ignored.

The activity adapter is isolated from usage. If thread monitoring fails, the panel keeps working and the usage indicator continues to refresh.

## Backend API

The Go backend listens on `127.0.0.1:${JUNIMO_BACKEND_PORT:-44832}`.

```text
GET /health
GET /state
```

Protocol version 5 state:

```json
{
  "revision": 12,
  "codex": {
    "status": "available",
    "primary": {
      "remainingPercent": 82,
      "windowDurationMinutes": 300,
      "resetsAt": 1783655023
    }
  },
  "activity": {
    "status": "available",
    "completionEvent": {
      "id": "<turn-id>",
      "threadId": "<thread-id>",
      "title": "Task title",
      "completedAt": 1783655000
    }
  }
}
```

`revision` increases monotonically so Swift can reject late snapshots. The latest completion event remains in later snapshots; Swift deduplicates by event ID before delivering sound.

## Codex Discovery

Junimo checks `JUNIMO_CODEX_EXECUTABLE`, `PATH`, common user install directories, the Codex app bundle, Homebrew, and `/usr/local/bin`. A candidate must be executable and successfully answer `--version` before it is selected.

## Quick Launch Configuration

New installations start with one Codex shortcut. Junimo creates and watches this
user-editable file:

```text
~/Library/Application Support/Junimo/quick-launch.json
```

Use the menu-bar command `Edit Quick Launches…` to open it. Add, remove, rename,
or reorder entries in the `items` array, then save. The expanded panel refreshes
without rebuilding or restarting Junimo. App updates do not overwrite an existing
file. Invalid JSON keeps the last valid catalog and shows a warning icon beside
`快速打开`.

The generated default is:

```json
{
  "iconOptions": ["app", "code", "website", "reading", "document", "tools", "data", "video", "music", "ai", "link"],
  "version": 1,
  "items": [
    {
      "id": "codex",
      "title": "Codex",
      "icon": "code",
      "type": "application",
      "target": "com.openai.codex"
    }
  ]
}
```

To add a website, append an item like this inside `items`:

```json
{
  "id": "docs",
  "title": "Docs",
  "icon": "document",
  "type": "url",
  "target": "https://example.com/docs"
}
```

To add another macOS application, use `"type": "application"` and place its
bundle identifier in `target`.

`type` accepts `url` for HTTP/HTTPS pages and `application` for a macOS bundle
identifier. Each item needs a unique alphanumeric `id`; `-` and `_` are also
allowed. The file must contain between 1 and 12 items. Up to four entries share
the row evenly; larger catalogs scroll horizontally.

Available `icon` presets:

- `app`: general applications
- `code`: development and terminals
- `website`: general websites
- `reading`: books and learning
- `document`: documents and notes
- `tools`: utilities
- `data`: dashboards and analytics
- `video`: video sites
- `music`: music sites
- `ai`: AI tools
- `link`: generic links

## Build And Test

Run the complete local validation:

```bash
scripts/verify_ci.sh
```

Useful narrower commands:

```bash
scripts/test.sh
scripts/build_app.sh
scripts/run.sh
```

`scripts/test.sh` covers Go activity and usage behavior, Swift DTO and shell state, a real Swift-to-Go v5 contract, and offscreen visual regression tests. The app bundle is written to `.build/app/Junimo.app`.
