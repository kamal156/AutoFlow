' Starts Windmill silently at Windows login - target of the "Windmill (start at login)"
' shortcut in the Startup folder. No window, no browser; use the desktop icon to open
' the UI. Recreate the Startup shortcut with:
'   cscript //nologo scripts\create-windmill-shortcut.vbs
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
here = fso.GetParentFolderName(WScript.ScriptFullName)

' 1. Hidden keep-alive: boots Ubuntu and holds it up (WSL otherwise stops it when idle).
sh.Run "wscript.exe //nologo """ & here & "\keep-wsl-alive.vbs""", 0, False

' 2. Make sure the stack is up even if it was left stopped with `docker compose stop`
'    (restart: unless-stopped alone would not bring it back then).
sh.Run "wsl.exe -d Ubuntu -u root -e sh -c ""for i in $(seq 120); do docker info >/dev/null 2>&1 && break; sleep 1; done; cd /mnt/d/AutoFlow && docker compose up -d""", 0, False
