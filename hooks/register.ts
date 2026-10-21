import type { Register } from 'claude-code'

// desktop-keepalive: answers the wake scheduled task without the model.
//
// The wake task fires every 15 minutes. Its stored prompt carries MARKER. When such a prompt
// arrives from a scheduled trigger, this hook does the whole job itself:
//   - no Claude restart since the last handled one -> drop the prompt (no model call at all)
//   - a restart -> send the wake-up message to the most recent sessions, plus the sessions in
//     alwaysWakeSessionIds, then drop the prompt
// On any failure it lets the prompt through: the prompt holds the full instructions, so the
// model then does the job exactly as it would without this plugin.
//
// Why a woken session matters: every restart of the Claude app (silent update, quit, Windows
// restart) disconnects all sessions from Remote Control, and a session reconnects only when it
// runs a turn. One short message makes it run a turn.

export const MARKER = '[[desktop-keepalive]]'

type SessionRow = {
  sessionId: string
  title?: string
  isArchived?: boolean
  isRunning?: boolean
  lastActivityAt?: string
  remoteControlActive?: boolean
  startedBy?: string
}

type TaskRow = { title?: string; taskId?: string }

type TaskRun = { session_id: string; status?: string; archived?: boolean }

export const register: Register = (on, options) => {
  const wakeCount = Math.max(0, Math.floor(Number(options.wakeCount ?? 3)))
  const alwaysWake = String(options.alwaysWakeSessionIds ?? '')
    .split(',')
    .map(s => s.trim())
    .filter(Boolean)
  const wakeMessage =
    String(options.wakeMessage ?? '').trim() ||
    'Automatic message: Claude was restarted. Do nothing and call no tool. Answer only: "awake"'
  const taskId = String(options.taskId ?? 'wake-sessions-after-restart')
  const archiveRuns = options.archiveOldRuns !== false

  on('prompt.submit', async ($, e, next) => {
    if (e.origin.kind !== 'scheduled-trigger' || !e.text.includes(MARKER)) return next(e)

    const script = `${$.plugin.root}/scripts/windows/wake-check.ps1`
    const run = async (...args: string[]) => {
      const r = await $.process.run(
        ['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script, ...args],
        { timeoutMs: 60_000 },
      )
      if (r.exitCode !== 0) throw new Error(`wake-check ${args[0]} exit ${r.exitCode}`)
      return r.stdout.trim()
    }
    // A tool call made by the plugin itself, not the model.
    const callText = async (tool: string, args: Record<string, unknown> = {}): Promise<string> => {
      const r = await $.tool.call({ tool, ...args } as never)
      if (r.deny !== undefined || r.isError) throw new Error(`${tool} failed`)
      return r.text ?? ''
    }
    const callJson = async <T>(tool: string, args: Record<string, unknown> = {}): Promise<T> =>
      JSON.parse(await callText(tool, args)) as T

    // Every run of the task is a session of its own. Archive (reversible, not delete) the earlier
    // finished runs so the session list keeps at most this one. Best effort: never blocks the job.
    const archiveOldRuns = async () => {
      if (!archiveRuns) return
      try {
        const { runs } = await callJson<{ runs?: TaskRun[] }>('mcp__scheduled-tasks__list_task_runs', { taskId, limit: 50 })
        for (const r of runs ?? []) {
          if (r.archived || r.status === 'running') continue // the current run is still "running"
          await callText('mcp__ccd_session_mgmt__archive_session', {
            session_id: r.session_id,
            reason: 'desktop-keepalive: finished run of the wake task',
          }).catch(() => {})
        }
      } catch {
        // listing failed - try again next run
      }
    }

    try {
      const { now, old } = JSON.parse(await run('check')) as { now: string; old: string }
      if (!now) throw new Error('no Claude start time')
      if (old === now) {
        await archiveOldRuns()
        return { drop: 'desktop-keepalive: no restart since the last check' }
      }
      if (!old) {
        await run('commit', now, 'first run, no wake')
        await archiveOldRuns()
        return { drop: 'desktop-keepalive: first run, start time saved' }
      }

      const tasks = await callJson<TaskRow[]>('mcp__scheduled-tasks__list_scheduled_tasks')
      const taskTitles = new Set(tasks.map(t => t.title).filter((t): t is string => !!t))
      const sessions = await callJson<SessionRow[]>('mcp__ccd_session_mgmt__list_sessions', { limit: 40 })
      const startedAt = Date.parse(now)

      const chosen = sessions
        .filter(s =>
          !s.isArchived &&
          !s.startedBy && // a child session's reply wakes its parent too, which then runs a turn of its own
          !(s.title && taskTitles.has(s.title)) && // runs of scheduled tasks are not the user's sessions
          !!s.lastActivityAt && Date.parse(s.lastActivityAt) < startedAt)
        .sort((a, b) => Date.parse(b.lastActivityAt!) - Date.parse(a.lastActivityAt!))
        .slice(0, wakeCount)

      // The fixed sessions are looked up one by one: the 40-row list may not reach them.
      for (const id of alwaysWake) {
        if (chosen.some(s => s.sessionId === id)) continue
        const s = await callJson<SessionRow>('mcp__ccd_session_mgmt__get_session', { session_id: id }).catch(() => undefined)
        if (s && !s.isArchived) chosen.push(s)
      }

      const woken: string[] = []
      for (const s of chosen) {
        if (s.remoteControlActive || s.isRunning) continue
        const sent = await callText('mcp__ccd_session_mgmt__send_message', {
          session_id: s.sessionId,
          message: wakeMessage,
        })
        // The result ends "(delivery: delivered|queued; message_id: ...)"; anything else was not delivered.
        if (/delivery:\s*(delivered|queued)/.test(sent)) woken.push(s.sessionId.replace('local_', '').slice(0, 8))
      }

      await run('commit', now, `woke ${woken.length}: ${woken.join(',') || '-'}`)
      await archiveOldRuns()
      return { drop: `desktop-keepalive: restart handled, woke ${woken.length} session(s)` }
    } catch (err) {
      const why = err instanceof Error ? err.message : String(err)
      await run('log', `fallback to model: ${why.replace(/[^\x20-\x7E]/g, '?').slice(0, 160)}`).catch(() => {})
      return next(e)
    }
  }).catch(($, e, next) => next(e)) // if the hook itself breaks, the prompt still reaches the model
}
