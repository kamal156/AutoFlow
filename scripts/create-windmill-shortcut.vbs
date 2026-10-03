' Creates (or refreshes) the "Windmill" desktop icon -> scripts\open-windmill.bat.
' VBScript rather than PowerShell: Quick Heal on this PC quarantines files that
' powershell.exe creates.   Run:  cscript //nologo scripts\create-windmill-shortcut.vbs
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
root = fso.GetParentFolderName(fso.GetParentFolderName(WScript.ScriptFullName))
lnkPath = sh.SpecialFolders("Desktop") & "\Windmill.lnk"

Set s = sh.CreateShortcut(lnkPath)
s.TargetPath = root & "\scripts\open-windmill.bat"
s.WorkingDirectory = root
s.IconLocation = root & "\assets\autoflow.ico,0"
s.Description = "Open Windmill (http://localhost:8000), starting it in WSL if needed"
s.WindowStyle = 1   ' normal: closes itself when Windmill is up, stays open to show any start-up error
s.Save
WScript.Echo "Desktop icon created: " & lnkPath
