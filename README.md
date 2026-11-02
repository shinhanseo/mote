# Mote

A local-first macOS companion for Codex Desktop. A little dust fairy keeps an eye on work while you focus elsewhere.

## What it does

- Frosted-glass, notch-safe panel with one scroll surface and muted olive accents.
- Multiple working conversations stay pinned after completion/read; new turns add or reorder them. Remove a pin without deleting the Codex chat, clean up completed pins, or undo a cleanup.
- A separate inbox for approval/input waits, unread replies and unacknowledged errors. Running tasks remain visible alongside other counts in the menu bar.
- Animated fairy states shared between menu and panel; rotating activity indicators; reduced-motion support.
- Direct links to named Codex conversations. Initial prompts/attachment metadata are never used as titles. Merely switching Codex tabs is not detected; sending a new message is.
- Wait duration measured from first detection, generic reasons derived from actual request types, no automatic approvals or replies.
- “Read later” lowers a reply’s visual priority without marking it read in Codex; a new turn restores normal priority.
- Category/sound preferences, 30-minute snooze, persistent deduplication and a 1.5-second grouping window for completion alerts. Read/resolved requests dismiss Mote’s delivered alerts.
- Nonactivating custom alerts on the pointer display, primary display or a named connected display. macOS system notifications remain an option.
- Login launch opt-in, single-instance lock, diagnostics, version display and manual GitHub source-update checks.
- A generated dust-fairy application icon. No API key or model charges are added by Mote.

## Run

Requires macOS 14+, Xcode command-line tools and Codex Desktop. Built locally on Apple Silicon with Swift 6.4.2.

```sh
./build.sh
open Mote.app
```

Keep the app in a stable location before enabling launch at login. macOS may require approval for the login item. Settings include a test alert and notification permission controls. Custom panels are independent of Focus and Notification Center; select macOS system notifications to use those OS delivery controls/history. Mote’s alert settings do not affect Codex’s own notifications.

Completion groups open the Mote inbox, individual alerts open the conversation. Custom alerts close after ten seconds and are queued (up to twenty groups). They do not steal keyboard focus. A disconnected named display falls back to the pointer display. Queue placement is chosen when shown, not continuously moved with the pointer.

## Privacy and compatibility

Mote reads local `$CODEX_HOME` (default `~/.codex`) databases read-only. It loads recent unarchived root threads and older active/pinned threads. It never edits Codex databases, reads authentication tokens, sends tool decisions or sends messages to the model. Its preferences, pin list and notification ledger stay locally in UserDefaults.

Live waiting/turn information uses the existing current-user-owned Codex Desktop IPC socket. This private version-dependent protocol is not a stable public integration contract. Unsupported versions show a diagnostic and fall back to database monitoring. A connection/revision gap clears stale live waiting states and requests fresh snapshots. Incoming snapshots are decoded transiently; only IDs, state flags, generic request-type labels and turn start/status metadata are retained. Message/tool bodies are not saved or logged.

Read receipts matching the published turn override stale unread stream flags. Unknown receipts fall back to live unread flags. In-progress records older than six hours are uncertain until live state confirms them. CLI-only sessions without a desktop owner cannot provide live wait status through this adapter. Free-form questions without a runtime wait flag are not guessed from text.

Notifications are deduplicated by thread, turn, kind and available request IDs for up to seven days, bounded at 2,000 entries. Repeated waits lacking IDs cannot always be distinguished. Startup snapshots do not replay historical completions. Disconnected periods may miss superseded intermediate turns. Mute/snooze does not queue a replay. Task titles may appear on the lock screen in system-alert mode.

Mote makes no network requests for task monitoring. Clicking **Update check** contacts only the public GitHub commit API and compares the app’s embedded source revision; no conversation data is sent. This is a source update check, not an automatic signed-app updater.

## Verification

```sh
python3 Tests/check_reader.py
Tests/check_live_state.sh
Tests/check_alert_placement.sh
Tests/check_monitor_flow.sh
./Mote.app/Contents/MacOS/Mote --diagnose
```

Reader fixtures cover recent/older active tasks, turn selection, titles, read receipts and stale state. Live-state tests cover waiting, request changes, revision gaps, short completions, persistence and parallel pin logic. Monitor-flow tests execute the actual Monitor code with isolated preferences and an injected notification sink: approval → question → resume → completion → read, notification grouping, reconnect dedup, cleanup/undo, deferred replies and snooze. They do not modify real conversations or preferences and are not proof of real OS notification delivery.

Screen placement tests include left/negative-coordinate and vertically arranged monitors. Native UI inspection verifies layout and settings. Actual multi-monitor alerts, Focus/lock-screen behavior and vendor changes should still be checked on the intended machines.

## Signing and distribution

Version: **0.2.0**. Default local builds are ad-hoc signed and are not notarized. Icon generation is reproducible with `Tools/GenerateIcon.swift` and `iconutil`.

For a Developer ID-signed, notarized archive, configure a **Developer ID Application** certificate/private key and an existing `notarytool` Keychain profile, then run:

```sh
MOTE_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
MOTE_NOTARY_PROFILE='your-profile' Tools/release.sh
```

The script enables hardened runtime signing, submits the zip, staples/validates the ticket and checks Gatekeeper before producing `release/Mote-0.2.0.zip`. No credentials are checked into this repository. A development certificate alone cannot produce this external-distribution build. Public releases are not published automatically.

For first-release account setup, universal DMG creation and verified website publication, see [DISTRIBUTION.md](DISTRIBUTION.md).

### 로컬 사용량 대시보드

메인 패널에서 Codex의 5시간·주간 잔여 비율과 초기화 시각을 확인할 수 있습니다. 최근 30개 대화의 로컬 기록에서 최신 한도 스냅샷을 읽으며, 1분 간격으로 재확인합니다. 새로고침은 서버 조회를 실행하지 않습니다. 오래된 기록과 초기화 시각이 지난 기록을 표시하며, 기록이 없으면 값을 만들지 않습니다. 계정 전환 시 이전 계정의 기록이 남아 있을 수 있습니다. 토큰 개수나 비용 추정치는 제공하지 않습니다.
