<!--
The prompt of the Claude scheduled task "wake-sessions-after-restart" (every 15 minutes: cron */15 * * * *).
The keepalive-setup skill creates the task from this file. Replace the three placeholders first:
  {{WAKE_COUNT}}          how many recent sessions to wake (default 3)
  {{ALWAYS_WAKE_IDS}}     comma-separated local_... session ids to always wake, or "none"
  {{WAKE_MESSAGE}}        the wake-up message (same as the plugin's wakeMessage option)
When the desktop-keepalive plugin is enabled it answers this task by itself (no model tokens).
The full instructions stay here so the task still works when the plugin is missing or fails.
Keep the marker line at the end exactly as it is.
Depends on the watchdog install (install-watchdog.ps1), which copies wake-check.ps1 to %USERPROFILE%\.claude\keepalive.
-->
A short automatic task: detect whether the Claude app was restarted, and if so, wake the recent sessions so they reconnect to the phone (Remote Control). Number of sessions to wake: {{WAKE_COUNT}}. Sessions to always wake: {{ALWAYS_WAKE_IDS}}.

Rules: change nothing else on the computer, touch no file except the state file, and send no message to any session not chosen by the rules here. When there was no restart, finish fast, with no further checks.

Step 1 - the start time of the Claude app that runs this run. Run in PowerShell:
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\keepalive\wake-check.ps1" check
It prints {"now":"...","old":"..."}. If "now" is empty: finish with the line "Claude start time not found" and do nothing else.

Step 2 - the decision:
- If "old" is empty (first run): run wake-check.ps1 commit <now> "first run, no wake" and finish with "First run, start time saved". Wake no session.
- If "old" equals "now": finish with one line "No restart". That's it.
- If "now" differs from "old": the app was restarted. Go on to step 3.

Step 3 - choosing the sessions (load tools with ToolSearch if needed: "select:mcp__ccd_session_mgmt__list_sessions,mcp__ccd_session_mgmt__get_session,mcp__ccd_session_mgmt__send_message,mcp__scheduled-tasks__list_scheduled_tasks"):
1. Call mcp__scheduled-tasks__list_scheduled_tasks and take the titles of all scheduled tasks.
2. Call mcp__ccd_session_mgmt__list_sessions with limit 40.
3. Keep only sessions that are not archived; whose title is not the title of any scheduled task (those are task runs, not the user's sessions); whose lastActivityAt is earlier than "now" (active before the restart); and that have no startedBy field (a session started from another session - when it answers, its parent is notified and runs a turn of its own, which wastes usage).
4. Sort by lastActivityAt, newest first, and take the number of sessions set above.
5. Add every "always wake" session id: call mcp__ccd_session_mgmt__get_session on it and add it if it is not archived (no duplicates).
6. Of those, wake only the ones whose remoteControlActive is false and that are not running now (isRunning false).

Step 4 - waking: for each chosen session call mcp__ccd_session_mgmt__send_message with its sessionId and exactly this message:
{{WAKE_MESSAGE}}

Step 5 - finish:
1. Call list_sessions again and check remoteControlActive for each woken session. If it is still false, that is fine - it can take a few seconds; say so.
2. Run wake-check.ps1 commit <now> "woke <n>" (only after the messages went out, so a failed run is retried next time).
3. Summarize in two lines: the restart time, which sessions were woken (title), and the phone connection state of each.
[[desktop-keepalive]] Marker for the desktop-keepalive plugin: when the plugin is enabled it answers this task by itself without the model. If this message reached you, the plugin did not manage - follow the instructions above as usual.
