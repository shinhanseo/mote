# Mote

A local-first macOS menu bar companion for Codex Desktop. A little dust fairy keeps track of work while you focus elsewhere.

## Features

- Animated menu-bar dust fairy: typing while running, raised waving hand while waiting, still while idle. Cached monochrome frames respect Reduce Motion and stop when displays sleep.
- Native frosted-glass panel, muted olive accents, notch-aware placement and Escape to dismiss.
- Recent Codex tasks, running/completed/failed/interrupted states and links back to their conversations.
- Live approval and answer waiting detection: raised hand, larger eyes, waiting count in the menu bar, waiting tasks first.
- Unread completed replies remain visible as a menu-bar reply count, a moving envelope and a dot in the task list. A matching `thread_read_receipts` row is authoritative and is refreshed every three seconds, overriding stale stream snapshots; the desktop `hasUnreadTurn` flag is a fallback when no matching receipt is available; no guess based on merely opening Mote. Approval/input waits take priority.
- Notifications for newly observed waits and observed running-to-completed/failed transitions; notification mute and test controls.
- Read-only local integration. No API key, backend, telemetry, automatic approvals or replies.

## Run and build

Requires macOS 14+, Xcode command-line tools and an installed Codex Desktop app. The development build was compiled on Apple Silicon with Swift 6.4.2.

```sh
./build.sh
open Mote.app
```

Click the dust icon in the menu bar. Click the notification permission control to enable macOS notifications, then Test Notification. If permission was denied, that control opens macOS notification settings. Focus modes and macOS settings can suppress delivery.

The build is ad-hoc signed for local development, not Developer ID signed or notarized. No login item is installed.

## Detection and limitations

The app reads `$CODEX_HOME` (default `~/.codex`) SQLite databases read-only every three seconds. It examines the latest turn of the 20 most recently updated, unarchived root threads. In-progress records older than six hours are marked unknown because abandoned records may survive an exited process.

For waiting states it connects to Codex Desktop's existing, current-user-owned Unix IPC socket and subscribes to thread snapshots and patches. It reads `threadRuntimeStatus.activeFlags` (`waitingOnApproval`, `waitingOnUserInput`) and request IDs. It never sends an approval decision or modifies the conversation. Full incoming frames are transiently decoded in memory; only runtime flags, unread state, revision and request IDs are retained. No conversation snapshot is logged or saved.

This desktop IPC protocol is private and version-dependent (currently stream version 11). It is not a stable public integration contract. Unsupported messages are ignored; a revision gap or dropped connection clears live waits and reconnects for fresh snapshots. While disconnected, ordinary database monitoring continues. CLI-only sessions without a desktop owner cannot provide live waiting status through this adapter. Free-form questions without a runtime waiting flag are not guessed from message text. Hook installation or trust bypass is not required.

Wait notifications are deduplicated by turn, waiting kind and available request IDs during a connection. A reconnect can notify about a still-pending request again. Startup snapshots intentionally notify about existing live waits, whereas old completed tasks do not trigger startup notifications. Extremely short turns occurring entirely between database polls may not produce a completion notification. Notification titles include task titles and can be shown on the lock screen.

Task links use `codex://threads/<id>` and depend on the installed desktop app supporting that route.

## Verification

```sh
python3 Tests/check_reader.py
Tests/check_live_state.sh
./Mote.app/Contents/MacOS/Mote --diagnose
```

Reader tests use isolated temporary databases and check running, completion, failure, interruption, stale records, latest-turn selection, unread-to-read receipt updates and ignoring receipts for a different published turn. Live reducer tests cover approval/answer transitions, clearing waits on resume, revision gaps, fresh snapshots and idle precedence. The running app has connected to the installed desktop IPC and received actual snapshots. A real end-to-end user approval/question followed by a visible macOS banner still needs manual verification; fixture tests are not proof of that flow.

The diagnostic command prints only task IDs and statuses. Source changes preserve the original Codex data and settings.
