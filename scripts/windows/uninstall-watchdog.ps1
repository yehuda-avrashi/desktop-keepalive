# Removes the watchdog task. The script copies in %USERPROFILE%\.claude\keepalive and the logs are kept
# (delete that folder yourself if you want them gone).
# ASCII-only on purpose (Windows PowerShell 5.1).
param([string]$TaskName = 'desktop-keepalive-watchdog')
$t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $t) { Write-Output "No task named $TaskName - nothing to do"; exit 0 }
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
Write-Output "Removed task $TaskName"
