---
name: keepalive-setup
description: Sets up, checks or removes the desktop-keepalive system on a Windows computer - the watchdog that relaunches Claude Desktop, the wake scheduled task that reconnects sessions to the phone, and the app settings that keep sessions reachable. Use when the user says "install keepalive", "set up the watchdog", "keep Claude alive", "Claude closes and my sessions disappear from the phone", "sessions don't show on mobile after a restart", "uninstall keepalive", or asks whether the keepalive system is working.
---

# desktop-keepalive: setup, check, removal

Three parts work together. Install all three unless the user asks for fewer.

| Part | What it does | Where it lives |
|---|---|---|
| Watchdog (Windows Task Scheduler) | Every 5 min and 1 min after logon: if Claude Desktop is closed, waits 90 s (an update reopens it within seconds) and opens it; if a stuck leftover process remains after Quit, stops it and opens Claude | `%USERPROFILE%\.claude\keepalive\` + task `desktop-keepalive-watchdog` |
| Wake task (Claude scheduled task) | Every 15 min: if the app was restarted since the last check, sends a short message to the most recent sessions so they run a turn and reconnect to Remote Control | `~/.claude/scheduled-tasks/wake-sessions-after-restart/` |
| This plugin's hook | Answers the wake task itself, so the 96 daily checks cost no model tokens; archives finished task runs | the plugin (enabled) |

Windows only (the scripts use Task Scheduler, WMI and the MSIX install of Claude Desktop).

## Install

Tell the user in one short list what will change before starting, then go on unless they object. Nothing here needs admin rights.

1. **Find the plugin's scripts folder.** Glob for `**/desktop-keepalive/**/scripts/windows/install-watchdog.ps1` under `~/.claude/plugins` (the installed copy) and use that folder.
2. **Check for an older setup** (see "Moving from an older setup" below): another Windows task that relaunches Claude (`Get-ScheduledTask | Where-Object TaskName -match 'claude|watchdog'`), another plugin that answers a wake task (`claude plugin list`), and an existing wake task (`mcp__scheduled-tasks__list_scheduled_tasks`). Two watchdogs or two wake tasks would race each other.
3. **Preview, then install the watchdog** (required: the wake task's fallback runs the copies it installs, and the installer stops with an explanation when Claude Desktop is not the Microsoft Store / MSIX install):
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<scripts>\install-watchdog.ps1" -WhatIf
   powershell -NoProfile -ExecutionPolicy Bypass -File "<scripts>\install-watchdog.ps1"
   ```
   Verify: `Get-ScheduledTask -TaskName desktop-keepalive-watchdog` is Ready, and a dry run decides correctly while Claude is open (it must exit silently, writing nothing):
   `powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\keepalive\claude-watchdog.ps1" -DryRun -GraceSeconds 0`
4. **Create the wake task.** Read `templates/wake-task-prompt.md` from the plugin, drop the HTML comment at the top, fill `{{WAKE_COUNT}}`, `{{ALWAYS_WAKE_IDS}}` and `{{WAKE_MESSAGE}}` with the same values as the plugin options (defaults: 3, none, the default message), keep the `[[desktop-keepalive]]` line last, and look the id up in `mcp__scheduled-tasks__list_scheduled_tasks` first:
   - not there: `mcp__scheduled-tasks__create_scheduled_task` with `taskId: wake-sessions-after-restart`, `title: Wake sessions after restart`, `description: Wakes recent sessions after a Claude Desktop restart so they reconnect to the phone`, `cronExpression: */15 * * * *`, `notifyOnCompletion: false`.
   - already there: `mcp__scheduled-tasks__update_scheduled_task` on it with the new prompt. Never accept a suggested free id such as `wake-sessions-after-restart-2`: two wake tasks would both run, and the plugin archives runs of the task named in its `taskId` option only.
   If the plugin option `taskId` differs, use that id everywhere.
5. **App settings** (via `mcp__ccd_settings__set_setting`, the user approves each): `connect_new_sessions_to_remote_control: true` (new sessions reach the phone by themselves), `keep_awake_while_working: true`, and ask about `keep_awake_on_battery` (laptop users usually want it on).
6. **Optional "waker" session.** Suggest one long-lived session the user can message from the phone with "wake session X": it is woken after every restart. Put its id in the plugin option `alwaysWakeSessionIds` (`/config` → desktop-keepalive) and in the task prompt. A small model (Haiku) is enough for it.
7. **Windows restarts at night** (the user does this, it is a system setting): gpedit.msc → Computer Configuration → Administrative Templates → Windows Components → Windows Update → Manage end user experience → "No auto-restart with logged on users for scheduled automatic updates installations" → Enabled; and Settings → Windows Update → Advanced options → "Notify me when a restart is required". Without it Windows may restart overnight; the watchdog then reopens Claude after logon, but only once the user logs in.
8. **First run.** Start the task once (`mcp__scheduled-tasks__run_scheduled_task`). The first run only saves the start time and wakes nobody: `%USERPROFILE%\.claude\state\desktop-keepalive\last-claude-start.txt` must exist afterwards.

## Moving from an older setup

If this computer already runs an earlier, hand-made version of the same system (a watchdog task, a local wake plugin, a wake task with another marker), switch over in this order, with the user's approval, so that exactly one of each runs:
1. Install the new watchdog, check that its task is Ready, then `Disable-ScheduledTask` the old one (disable, never delete, so it can be turned back on).
2. `claude plugin disable <old plugin>` for the old wake plugin.
3. Update the existing wake task's prompt to the template (the `[[desktop-keepalive]]` marker), keeping its id, or set the plugin option `taskId` to the existing id.
4. Run the new first run (Install, step 8) so the new state file exists: the new system keeps its own state in `%USERPROFILE%\.claude\state\desktop-keepalive`, so the first run wakes nobody.
5. Update any document or script that creates the old pause file: the new pause file is `%USERPROFILE%\.claude\state\desktop-keepalive\watchdog-pause`.

## Check that it works

- Watchdog actions: `%USERPROFILE%\.claude\keepalive\claude-watchdog.log` (a line only when it acted: "launching", "stopping the leftover", "Claude is up again").
- Wake actions: `%USERPROFILE%\.claude\state\desktop-keepalive\wake.log` (a line only on a real restart or when the plugin fell back to the model).
- End to end: ask the user to Quit Claude from the tray. Within about 4 minutes Claude reopens signed in, and within the next wake run the recent sessions show `remoteControlActive: true` in `list_sessions`.
- Task runs cost nothing when the plugin works: a run with no restart ends in seconds with no turns.

## Pause the watchdog

Any procedure that needs Claude closed (a full Quit to edit `claude_desktop_config.json`, a script that kills Claude) creates `%USERPROFILE%\.claude\state\desktop-keepalive\watchdog-pause` first and deletes it at the end. A pause older than 3 hours is removed by itself.

## Update the plugin

An installed plugin runs from a copy in `~/.claude/plugins/cache`. After editing: raise `version` in `.claude-plugin/plugin.json`, then `claude plugin marketplace update desktop-keepalive` and `claude plugin update desktop-keepalive@desktop-keepalive`. New sessions and scheduled runs load the new version. Re-run `install-watchdog.ps1` to refresh the watchdog copies.

## Remove

1. `powershell -NoProfile -ExecutionPolicy Bypass -File "<scripts>\uninstall-watchdog.ps1"` (removes the task; the copies and logs stay in `%USERPROFILE%\.claude\keepalive`).
2. Disable or delete the wake task in the app (Scheduled tasks), with the user's approval.
3. `claude plugin uninstall desktop-keepalive@desktop-keepalive`.
