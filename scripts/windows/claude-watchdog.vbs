' Silent launcher for claude-watchdog.ps1 (same folder). wscript is a GUI host, so no console window flashes.
' The path is taken from this file's own location, so it works under any user name, Unicode included.
Dim fso, dir
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & dir & "\claude-watchdog.ps1""", 0, False
