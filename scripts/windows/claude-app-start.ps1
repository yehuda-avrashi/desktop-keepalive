# Prints the start time (UTC, ISO) of the Claude Desktop main process that runs the CALLING session.
# Used by the wake task (and the desktop-keepalive plugin) to detect that Claude was restarted.
# It walks up from this PowerShell process to the Claude app, so a stuck leftover Claude process
# (an old main process that never exited after Quit) can never be picked by mistake.
# ASCII-only on purpose (Windows PowerShell 5.1 misreads UTF-8 without BOM).
$all = @{}
Get-CimInstance Win32_Process | ForEach-Object { $all[[int]$_.ProcessId] = $_ }
$cur = $all[[int]$PID]
$main = $null
for ($n = 0; $n -lt 30 -and $cur; $n++) {
    if ($cur.ExecutablePath -like '*\WindowsApps\Claude_*') { $main = $cur }
    elseif ($main) { break }   # passed the topmost Claude app process
    $cur = $all[[int]$cur.ParentProcessId]
}
if (-not $main) { Write-Output 'NOT_FOUND'; exit 1 }
$main.CreationDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
