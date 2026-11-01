# Mote

A local-first macOS menu bar companion for Codex Desktop. A little dust fairy keeps track of work while you focus elsewhere.

## Features

- Animated menu-bar dust fairy: typing while running, raised waving hand while waiting, still while idle. Cached monochrome frames respect Reduce Motion and stop when displays sleep.
- Native frosted-glass panel, muted olive accents, notch-aware placement and Escape to dismiss.
- Conversation names match Codex’s `threads.name` field; unnamed chats show “제목 없는 대화”, never the first prompt or attachment metadata. Names refresh on the normal polling interval.
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

The app reads `$CODEX_HOME` (default `~/.codex`) SQLite databases read-only every three seconds. It examines recent unarchived root threads plus older persisted in-progress roots. In-progress records older than six hours are marked unknown because abandoned records may survive an exited process.

For waiting states it connects to Codex Desktop's existing, current-user-owned Unix IPC socket and subscribes to thread snapshots and patches. It reads `threadRuntimeStatus.activeFlags` (`waitingOnApproval`, `waitingOnUserInput`) and request IDs. It never sends an approval decision or modifies the conversation. Full incoming frames are transiently decoded in memory; only runtime flags, unread state, revision and request IDs are retained. No conversation snapshot is logged or saved.

This desktop IPC protocol is private and version-dependent (currently stream version 11). It is not a stable public integration contract. Unsupported messages are ignored; a revision gap or dropped connection clears live waits and reconnects for fresh snapshots. While disconnected, ordinary database monitoring continues. CLI-only sessions without a desktop owner cannot provide live waiting status through this adapter. Free-form questions without a runtime waiting flag are not guessed from message text. Hook installation or trust bypass is not required.

Wait notifications are deduplicated persistently by thread, turn, waiting kind and available request IDs. Startup snapshots intentionally notify about existing live waits, whereas old completed tasks do not trigger startup notifications. Short turns are detected through live terminal metadata and new completed turns between polls. Disconnected periods may still miss intermediate turns superseded before the next poll. Notification titles include task titles and can be shown on the lock screen.

Task links use `codex://threads/<id>` and depend on the installed desktop app supporting that route.

## Verification

```sh
python3 Tests/check_reader.py
Tests/check_live_state.sh
./Mote.app/Contents/MacOS/Mote --diagnose
```

Reader tests use isolated temporary databases and check running, completion, failure, interruption, stale records, latest-turn selection, unread-to-read receipt updates and ignoring receipts for a different published turn. Live reducer tests cover approval/answer transitions, clearing waits on resume, revision gaps, fresh snapshots and idle precedence. The running app has connected to the installed desktop IPC and received actual snapshots. The inbox and settings have been inspected in the native UI, and a second process was verified to exit immediately. Real end-to-end user approvals/questions followed by a visible macOS banner still need verification; fixture tests are not proof of that flow.

The diagnostic command prints only task IDs and statuses. Source changes preserve the original Codex data and settings.

## Work inbox and preferences

The default inbox separates approval/input waits, unread replies and errors from running tasks. A persistent Current Conversation sits above the inbox regardless of completion/read state. It automatically follows the newest started conversation turn, including a new chat or a new message in an existing chat, using turn start time and turn ID rather than background update time. It also changes when a row successfully opens Codex, or via the row context menu. Completed turns keep their pin; old snapshots cannot steal it. It is retained outside the recent-20 window. Merely switching Codex tabs without sending a message is not tracked; new turns are detected through live metadata or the three-second database poll. All recent tasks are available under All. Running rows show a rotating olive activity ring and three cycling dots; these indicate activity, not a measured completion percentage, and respect Reduce Motion. Clicking a row opens that conversation immediately; errors can be acknowledged through its context menu without modifying Codex. Wait elapsed time starts when Mote first detects that request, persists locally and is explicitly labeled as detection-based.

Settings expose separate attention, completion and error alerts, attention/completion sounds, a persistent 30-minute snooze and opt-in login launch via SMAppService. Completion sound defaults to off. Login registration can require macOS approval; keep the app at a stable location before enabling it. No login registration is performed by default. An advisory process lock prevents concurrent Mote instances.

Recent history is limited to 20 rows, but persisted in-progress root threads outside that window are also monitored, including stale rows whose live state can subsequently confirm activity. Nonrecent finished threads do not accumulate forever. Successful terminal transitions are detected both by polling (including a new turn already completed between polls) and live canonical turn metadata. Live metadata retains turn ID, status and start time only, never text. Startup/reconnect snapshots of historical completions are not re-notified.

Notification IDs are deduplicated across live updates, polls and app restarts using a local ledger capped at 2,000 entries, retaining up to seven days. Distinct request IDs within one turn can notify separately. A transport without request IDs cannot reliably distinguish consecutive identical waits within the same turn. Muted/snoozed/disabled events are not queued for replay. No automatic approvals or replies are introduced.

Both menu and panel use the same animated monochrome fairy frames: working, approval, question, unread envelope, error and idle. Reduce Motion uses still frames. The inbox is a local companion, not a second task execution engine.
