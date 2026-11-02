<div align="center">

<img src="website/assets/mote-dust-soft.svg" width="150" alt="Mote, a little black dust companion">

# Mote

**When Codex needs you, Mote lets you know.**  
A little companion in your Mac menu bar. Task done, approval needed, or a question waiting — keep working until you are needed.

[**Download for Mac ↓**](https://github.com/shinhanseo/mote/releases/latest) · [Website & interactive demo ↗](https://shinhanseo.github.io/mote/en/) · [한국어](README.md)

macOS 14+ · Apple Silicon & Intel · Free & open source

</div>

## Stay in your flow

- **Catch approval and input waits.** Distinct states, short notifications, and wait durations.
- **Keep several chats in view.** Pin chats, spot unread replies and errors, and open the right Codex conversation.
- **Get alerts where you work.** Choose the pointer display, primary display, another connected screen, or macOS system notifications.
- **Come back when ready.** Ten-minute snooze, wait reminders, and a summary of unresolved tasks when you return.
- **Jump back with the keyboard.** Control+Option+Space opens the oldest waiting chat; customize or disable it in Settings.
- **Check usage on demand.** Collapsed five-hour and weekly limits, reset estimates, and threshold alerts, based on local records.
- **Know when state is uncertain.** Network-path warnings, last activity, and long-silent tasks.
- **Keep titles private.** Privacy mode hides chat titles, projects and request details. English and Korean interfaces are included.

Usage records can be stale or differ from actual limits. Reset alerts are time estimates. Away handling is separate from macOS Focus integration.

## Install once. Update in the app.

1. Download the DMG from the [latest release](https://github.com/shinhanseo/mote/releases/latest).
2. Drag Mote to **Applications**, then launch it and allow notifications.
3. Work in Codex Desktop as usual.

Public releases are Developer ID signed and Apple notarized. Requires macOS 14+ and Codex Desktop.

On Mote **0.4.0+**, choose **Check for updates and install** in Settings to download, install and relaunch. Users on 0.3.1 or earlier need one manual replacement. Do not run the app from the mounted DMG.

## Your work stays on your Mac

Mote reads local Codex records and session state. It does not send code or conversations to a Mote server, require an account or API key, or approve actions and send replies for you. Update checks and installation contact GitHub Releases and the signed appcast on the Mote website. Codex's own AI service is separate.

Detection relies on private, version-dependent Codex Desktop data formats. Codex updates may require compatibility fixes; check Mote Diagnostics or [report an issue](https://github.com/shinhanseo/mote/issues). Other AI tools and iPhone pairing are not currently supported.

## Build from source

Requires Xcode command-line tools.

```sh
git clone https://github.com/shinhanseo/mote.git
cd mote
./build.sh
open Mote.app
```

Default local builds are ad-hoc signed, not notarized.

[Technical notes & tests](docs/DEVELOPMENT.md) · [Signing & distribution](DISTRIBUTION.md) · [Releases](https://github.com/shinhanseo/mote/releases)

Independent app. Not affiliated with OpenAI.
