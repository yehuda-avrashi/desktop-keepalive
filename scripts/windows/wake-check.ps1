# Helper for the desktop-keepalive plugin and the wake scheduled task.
#   wake-check.ps1 check                  -> one JSON line: {"now":"...","old":"..."}
#   wake-check.ps1 commit <now> <note>    -> saves <now> as the last handled Claude start, logs <note>
#   wake-check.ps1 log <note>             -> writes one line to the log
# "now" is the start time of the Claude app that runs the calling session (see claude-app-start.ps1).
# State and log live in %USERPROFILE%\.claude\state\desktop-keepalive (override with -StateDir).
# ASCII-only on purpose (Windows PowerShell 5.1).
param(
    [Parameter(Position = 0)][string]$Mode = 'check',
    [Parameter(Position = 1)][string]$Now = '',
    [Parameter(Position = 2)][string]$Note = '',
    [string]$StateDir = (Join-Path $env:USERPROFILE '.claude\state\desktop-keepalive')
)
$ErrorActionPreference = 'Stop'
$marker = Join-Path $StateDir 'last-claude-start.txt'
$log    = Join-Path $StateDir 'wake.log'

function Write-WakeLog([string]$line) {
    if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Force $StateDir | Out-Null }
    if ((Test-Path $log) -and (Get-Item $log).Length -gt 200KB) { Move-Item $log "$log.old" -Force }
    Add-Content -Path $log -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $line) -Encoding ascii
}

if ($Mode -eq 'check') {
    $start = (& (Join-Path $PSScriptRoot 'claude-app-start.ps1') | Select-Object -Last 1)
    if (-not $start -or $start -eq 'NOT_FOUND') { $start = '' }
    $old = if (Test-Path $marker) { (Get-Content $marker -Raw).Trim() } else { '' }
    Write-Output (@{ now = $start; old = $old } | ConvertTo-Json -Compress)
    exit 0
}

if ($Mode -eq 'commit') {
    if (-not $Now) { Write-Error 'commit needs <now>'; exit 1 }
    if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Force $StateDir | Out-Null }
    Set-Content -Path $marker -Value $Now -Encoding ascii
    Write-WakeLog ("start={0} {1}" -f $Now, $Note)
    Write-Output 'ok'
    exit 0
}

if ($Mode -eq 'log') {
    $msg = if ($Note) { $Note } else { $Now }
    Write-WakeLog $msg
    Write-Output 'ok'
    exit 0
}

Write-Error "unknown mode: $Mode"
exit 1
