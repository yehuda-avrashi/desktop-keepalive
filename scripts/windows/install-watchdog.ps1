# Installs the Claude Desktop watchdog on this Windows user account:
#  1. copies the scripts of this folder to %USERPROFILE%\.claude\keepalive
#  2. registers a Task Scheduler task that runs the watchdog every 5 minutes and 1 minute after logon,
#     on battery too, with no console window.
# Runs as the current user, no admin rights needed. Run again to update; uninstall-watchdog.ps1 removes it.
#   -WhatIf     show what would be done, change nothing
#   -TaskName   default "desktop-keepalive-watchdog"
# ASCII-only on purpose (Windows PowerShell 5.1).
param(
    [switch]$WhatIf,
    [string]$TaskName = 'desktop-keepalive-watchdog',
    [string]$InstallDir = (Join-Path $env:USERPROFILE '.claude\keepalive')
)
$ErrorActionPreference = 'Stop'
$src   = $PSScriptRoot
$files = 'claude-watchdog.ps1', 'claude-watchdog.vbs', 'claude-app-start.ps1', 'wake-check.ps1'

# The watchdog and the restart detection work with the Microsoft Store (MSIX) install of Claude Desktop only.
$pkg = Get-AppxPackage -Name 'Claude' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $pkg) {
    Write-Output 'Claude Desktop (Microsoft Store / MSIX package "Claude") was not found for this user.'
    Write-Output 'The watchdog only supports that install. Nothing was changed.'
    exit 1
}
Write-Output "Claude Desktop : $($pkg.PackageFamilyName) $($pkg.Version)"
Write-Output "Install folder : $InstallDir"
Write-Output "Task name      : $TaskName (every 5 min + 1 min after logon, battery allowed)"
if ($WhatIf) {
    foreach ($f in $files) { Write-Output "would copy     : $f" }
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Write-Output ("existing task  : " + $(if ($existing) { 'yes - would be replaced' } else { 'no' }))
    exit 0
}

if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Force $InstallDir | Out-Null }
foreach ($f in $files) { Copy-Item (Join-Path $src $f) (Join-Path $InstallDir $f) -Force }

$vbs      = Join-Path $InstallDir 'claude-watchdog.vbs'
$action   = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('"' + $vbs + '"')
$every5   = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
              -RepetitionInterval (New-TimeSpan -Minutes 5)
$atLogon  = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$atLogon.Delay = 'PT1M'
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
              -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($every5, $atLogon) -Settings $settings `
    -Principal $principal -Force `
    -Description 'Relaunches Claude Desktop if it is not running (desktop-keepalive). Pause: create %USERPROFILE%\.claude\state\desktop-keepalive\watchdog-pause (expires after 3h).' | Out-Null

$t = Get-ScheduledTask -TaskName $TaskName
Write-Output "Installed. Task state: $($t.State)"
Write-Output "Watchdog log: $(Join-Path $InstallDir 'claude-watchdog.log') (written only when it acts)"
