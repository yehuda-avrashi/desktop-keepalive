# claude-watchdog: relaunch Claude Desktop when it is not running (crash, quit, update, Windows restart).
# Runs from Task Scheduler every 5 minutes and at logon, through claude-watchdog.vbs (no console window).
# Once Claude is up again, the wake scheduled task wakes the recent sessions so they reconnect to the phone.
#
# Two "not running" cases:
#  1. No Claude main process at all (crash, Windows restart, normal quit).
#  2. Stuck leftover: Claude logged a finished quit ("willQuit ... so quitting"), but its main process
#     never exited. It holds about 1GB and, while it lives, a newly opened Claude may start signed out.
#     The watchdog stops that leftover, then opens Claude.
#
# Pause on purpose (e.g. a full Quit to edit claude_desktop_config.json): create the pause file
#   %USERPROFILE%\.claude\state\desktop-keepalive\watchdog-pause
# and delete it when done. A pause older than 3 hours is removed by itself, so a forgotten pause
# never leaves Claude closed for good.
#
# Test flags: -DryRun (decide and log, never stop or launch), -TestMissing (pretend Claude is not running),
# -LogPath <file> (read another main.log), -GraceSeconds <n>.
# Script is ASCII-only on purpose: Windows PowerShell 5.1 misreads UTF-8 without BOM.
param(
    [switch]$DryRun,
    [switch]$TestMissing,
    [string]$LogPath = "$env:LOCALAPPDATA\Claude\Logs\main.log",  # Claude's own log
    [int]$GraceSeconds = 90
)

$ErrorActionPreference = 'Stop'
$base     = Split-Path -Parent $MyInvocation.MyCommand.Path
$log      = Join-Path $base 'claude-watchdog.log'
$stateDir = Join-Path $env:USERPROFILE '.claude\state\desktop-keepalive'
$pause    = Join-Path $stateDir 'watchdog-pause'

function Write-Log([string]$msg) {
    if ((Test-Path $log) -and (Get-Item $log).Length -gt 200KB) {
        Move-Item $log "$log.old" -Force
    }
    Add-Content -Path $log -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $msg) -Encoding ascii
}

# The Claude Desktop app id for "explorer shell:AppsFolder\<id>" (MSIX install).
function Get-ClaudeAppId {
    $pkg = Get-AppxPackage -Name 'Claude' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pkg) { return "$($pkg.PackageFamilyName)!Claude" }
    return 'Claude_pzs8sxrjxfjjc!Claude'
}

# All Claude app processes (the Claude Code engine lives elsewhere, under AppData, and is not counted).
function Get-ClaudeProcs {
    if ($TestMissing) { return @() }
    @(Get-CimInstance Win32_Process -Filter "Name='claude.exe'" |
        Where-Object { $_.ExecutablePath -like '*\WindowsApps\Claude_*' })
}

# True when Claude's log says the app finished quitting and nothing started after that.
function Test-QuitLogged {
    if (-not (Test-Path $LogPath)) { return $false }
    $tail = @(Get-Content -Path $LogPath -Tail 400 -Encoding UTF8)
    $lastStart = -1; $lastQuit = -1
    for ($i = 0; $i -lt $tail.Count; $i++) {
        $line = $tail[$i]
        if ($line -like '*willQuit: handler is ready for quit*') { $lastQuit = $i }
        elseif ($line -like '*] Starting app {*') {
            # A second launch while Claude is open logs "Starting app" then hands over and exits: not a real start.
            $handover = $false
            for ($j = $i + 1; $j -le [Math]::Min($i + 4, $tail.Count - 1); $j++) {
                if ($tail[$j] -like "*Quit requested before 'ready'*") { $handover = $true }
            }
            if (-not $handover) { $lastStart = $i }
        }
    }
    return ($lastQuit -gt $lastStart)
}

try {
    if (Test-Path $pause) {
        $ageH = ((Get-Date) - (Get-Item $pause).LastWriteTime).TotalHours
        if ($ageH -lt 3) { exit 0 }
        Remove-Item $pause -Force
        Write-Log "pause file older than 3h - removed, watching again"
    }

    $procs = Get-ClaudeProcs
    if ($procs.Count -gt 0) {
        if (-not (Test-QuitLogged)) { exit 0 }          # Claude is running normally
        $idle = ((Get-Date) - (Get-Item $LogPath).LastWriteTime).TotalSeconds
        if ($idle -lt $GraceSeconds) { exit 0 }         # quit just happened (maybe an update relaunch) - wait
        if (-not (Test-QuitLogged)) { exit 0 }

        $ids = ($procs | ForEach-Object { $_.ProcessId }) -join ','
        if ($DryRun) { Write-Log "DRY RUN: Claude logged quit but $($procs.Count) process(es) remain ($ids) - would stop them and launch"; exit 0 }
        Write-Log "Claude logged quit but $($procs.Count) process(es) remain ($ids) - stopping the leftover"
        $procs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 3
    }
    else {
        # Grace period: an app update closes and reopens Claude within seconds; do not race it.
        Start-Sleep -Seconds $GraceSeconds
        if ((Get-ClaudeProcs).Count -gt 0) { exit 0 }
        if ($DryRun) { Write-Log "DRY RUN: Claude not running for $GraceSeconds s - would launch it"; exit 0 }
        Write-Log "Claude not running for $GraceSeconds s - launching"
    }

    Start-Process -FilePath 'explorer.exe' -ArgumentList ("shell:AppsFolder\" + (Get-ClaudeAppId))
    Start-Sleep -Seconds 45
    if ((Get-ClaudeProcs).Count -gt 0 -and -not (Test-QuitLogged)) { Write-Log "Claude is up again" }
    else { Write-Log "Claude did not start after 45 s - will retry next run" }
}
catch {
    Write-Log ("ERROR: " + $_.Exception.Message)
    exit 1
}
