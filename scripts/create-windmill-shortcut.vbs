' Creates (or refreshes) both Windmill shortcuts:
'   Desktop\Windmill.lnk                      -> scripts\open-windmill.bat (start if needed + open UI)
'   Startup\Windmill (start at login).lnk     -> scripts\windmill-at-login.vbs (silent start, no browser)
' VBScript rather than PowerShell: Quick Heal on this PC quarantines files that
' powershell.exe creates.   Run:  cscript //nologo scripts\create-windmill-shortcut.vbs
' To stop starting at login, delete the shortcut from shell:startup (Win+R -> shell:startup).
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
root = fso.GetParentFolderName(fso.GetParentFolderName(WScript.ScriptFullName))
icon = root & "\assets\autoflow.ico,0"

lnkPath = sh.SpecialFolders("Desktop") & "\Windmill.lnk"
Set s = sh.CreateShortcut(lnkPath)
s.TargetPath = root & "\scripts\open-windmill.bat"
s.WorkingDirectory = root
s.IconLocation = icon
s.Description = "Open Windmill (http://localhost:8000), starting it in WSL if needed"
s.WindowStyle = 1   ' normal: closes itself when Windmill is up, stays open to show any start-up error
s.Save
WScript.Echo "Desktop icon created: " & lnkPath

startPath = sh.SpecialFolders("Startup") & "\Windmill (start at login).lnk"
Set s = sh.CreateShortcut(startPath)
s.TargetPath = sh.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\wscript.exe"
s.Arguments = "//nologo """ & root & "\scripts\windmill-at-login.vbs"""
s.WorkingDirectory = root
s.IconLocation = icon
s.Description = "Start Windmill in WSL at login (no window, no browser)"
s.Save
WScript.Echo "Startup entry created: " & startPath
