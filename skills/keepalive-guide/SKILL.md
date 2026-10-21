---
name: keepalive-guide
description: How Claude Desktop sessions stay alive and reachable from the phone, and how to diagnose when they don't - why the app "closes every few hours", why sessions vanish from mobile after a restart, how to wake a sleeping session, how to work with sessions from the phone, and the known traps (idle timeout, child sessions, mobile archive, stuck leftover process, scheduled-task runs). Use when the user says "Claude keeps closing", "Claude crashed", "all my sessions dropped", "I can't see today's sessions on my phone", "the session on my phone is archived", "wake session X", "open a session from my phone", or asks why a session stopped answering.
---

# Keeping Claude Desktop sessions alive: how it works and how to diagnose

## The core fact

Every restart of the Claude Desktop app disconnects **all** existing sessions from Remote Control (the phone and claude.ai/code), and they do not come back by themselves. A session reconnects only when it runs a turn. The setting `connect_new_sessions_to_remote_control` connects a session when it runs a turn - it does not reconnect sleeping sessions after a restart. So after every restart something has to send each important session a message. That is what the wake task of desktop-keepalive does.

## Why "Claude closes every few hours" (it is almost never a crash)

Check in this order. Logs: `%LOCALAPPDATA%\Claude\Logs\main*.log` (local time) and the Windows System event log.

1. **Silent app update.** `[stealth-update] Triggering stealth update after idle timeout` in main.log. The app closes and reopens within about 5 seconds when no session is working, a few times a month. It waits while a session works (`Deferring auto-restart ... Claude is working`). There is no setting to turn it off.
2. **Windows restart for an update.** System event 1074 by `MoUsoCoreWorker.exe`, usually right after the end of "active hours". Claude does not start by itself after a reboot. Fix: the group-policy setting "No auto-restart with logged on users for scheduled automatic updates installations" (the user sets it), plus the watchdog (reopens Claude after logon).
3. **Load.** Dozens of open sessions each keep their own helper processes (every MCP server, per session). Hundreds of processes and >10GB lead to `Main webview is unresponsive, will kill and reload`. Look for `process-memory` and `event-loop-stall` in main.log. Fix: archive finished sessions instead of keeping 20-30 open.
4. **Manual.** `beforeQuit: vetoed by before-quit interceptor` then `Stopping N active session(s)` = someone pressed Quit and confirmed the "active sessions" dialog. `Windows session ending (shutdown)` = the computer was shut down.

Quick check for a real crash: Crashpad reports and Application events 1000/1002 for claude.exe. `previous_quit_clean: false` after a Windows shutdown is normal, not a crash.

## Traps (all observed in practice)

- **Stuck leftover after Quit.** The app logs `willQuit: handler is ready for quit, so quitting`, but its main process (with ~5 helpers, ~1GB) never exits. A watchdog that only checks "is claude.exe running" thinks Claude is open; a newly opened Claude may then start **signed out**. The watchdog here reads main.log to tell a real run from a leftover and stops the leftover before relaunching.
- **Do not count the Claude Code engine.** `AppData\Roaming\Claude\claude-code\...\claude.exe` is the engine, not the app. Only processes under `WindowsApps\Claude_*` are the app.
- **Restart detection must use the right process.** Take the start time of the app process that runs the current session (walk up the parent chain), never "the oldest claude.exe": that can be a stuck leftover and hides the restart.
- **No session can wait for a restart.** A restart stops every session (`lost /loop or background work`), and an idle session shuts down after 15 minutes (`idle timeout 900s`). The only thing the app starts by itself after launch is a scheduled task, and each run of it is a new session. That is why the wake job is a scheduled task every 15 minutes, and why the plugin answers it without the model (otherwise ~250K tokens per check, 96 times a day).
- **Do not wake child sessions.** A session with `startedBy` was started from another session. When it answers, its parent is notified and runs a turn of its own - possibly a long, expensive one. Wake only top-level sessions.
- **Do not wake scheduled-task runs.** They never connect to the phone anyway, and they are not the user's sessions. Filter them out by matching titles against `list_scheduled_tasks`.
- **Mobile archive.** When Claude closes on the computer, claude.ai archives the phone copy of each connected session; on the computer it is not archived (`isArchived: false`). When the desktop session runs a turn and reconnects, it unarchives itself (`[bridge:init] Unarchived reaped session ... before reattach`). So "my session is archived on the phone" = wake it on the computer.
- **`set_remote_control` fails on a sleeping session** ("Remote Control requires an active session. Send a message first"). Send it a message first; at the start of its turn the app reconnects it with the same claude.ai/code link.
- **Each wake-task run is a session.** Without cleanup the session list fills with runs. The plugin archives finished runs (archive, not delete: deleting asks the user every time and cannot be undone).
- **Scripts on Windows PowerShell 5.1** must be ASCII-only (UTF-8 without BOM is misread), and a user folder with non-ASCII letters breaks `python "<path>"` style calls: build paths from `$env:USERPROFILE` or from the script's own location, never hard-code them.

## Working with sessions from the phone

- **Wake a session:** send it a short technical message ("automatic message, do nothing, answer only: ready"). Verify with `list_sessions` (`remoteControlActive: true`) or main.log (`Enabling remote control for session`, `bridge_state: "connected"`).
- **A waker session:** keep one long-lived session (a small model is enough) that is woken after every restart. From the phone, ask it "wake session X" and it sends X the message. Put its id in the plugin option `alwaysWakeSessionIds`.
- **Start new work from the phone:** cards that offer a new session need a click on the computer. Instead, wake an old session that is already connected, let the user clear it (`/clear`) from the phone, then send it the task. A short session on a related topic works best.
- **A scheduled-task run that waits for approval** can be connected to the phone (`set_remote_control` while it runs) so the user approves from the phone. Such runs do receive the user's own phone messages; only session-to-session `send_message` is refused for them. A run that "does not answer" is usually in the middle of a long turn - check `lastActivityAt` (UTC) and recently changed files before calling it stuck, and never stop someone's session without asking.

## App settings that matter

| Setting | Recommended | Why |
|---|---|---|
| `connect_new_sessions_to_remote_control` | on | new sessions reach the phone without action |
| `keep_awake_while_working` | on | idle sleep does not cut a working session (a closed lid still sleeps) |
| `keep_awake_on_battery` | on for laptops | the same on battery |
| `auto_archive_inactive_days` | the user's choice | fewer open sessions = less load; archived sessions are not woken |

## Diagnosis checklist: "my sessions are gone from the phone"

1. `list_sessions` - is `remoteControlActive` false for all but the current one? Then the app restarted.
2. main.log - find the last `Starting app` / `Version changed` / `stealth-update` / `beforeQuit` and its time.
3. Was the wake task run after that time? Look at `wake.log` and the task's runs. No run → was Claude closed (watchdog log) or the task disabled?
4. Did the plugin fall back to the model? A `fallback to model:` line in `wake.log` names the reason; the model then did the job, so check that run's transcript.
5. Still disconnected: wake the sessions by hand with a message, then verify.
