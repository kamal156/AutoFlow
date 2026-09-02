<#
.SYNOPSIS
  Creates (or refreshes) the AutoFlow desktop icon. Double-clicking it runs
  AutoFlow.bat, which starts the local Windmill host and opens the UI.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$lnk  = Join-Path ([Environment]::GetFolderPath('Desktop')) 'AutoFlow.lnk'

$sh = New-Object -ComObject WScript.Shell
$s = $sh.CreateShortcut($lnk)
$s.TargetPath       = Join-Path $root 'AutoFlow.bat'
$s.WorkingDirectory = $root
$s.IconLocation     = (Join-Path $root 'assets\autoflow.ico') + ',0'
$s.Description      = 'Start AutoFlow (local Windmill at http://localhost:8000)'
$s.WindowStyle      = 1   # normal window so the first-run download and any error are visible
$s.Save()
Write-Host "Desktop icon created: $lnk" -ForegroundColor Green
