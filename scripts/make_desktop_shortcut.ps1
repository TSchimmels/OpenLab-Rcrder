# Creates an "OpenLab Recorder" shortcut on the Windows Desktop.
# Double-clicking it runs launch.py: auto-detect the OpenBCI dongle, open
# LabRecorder, and start streaming. Identity-free (resolves paths at runtime).
#   Run:  powershell -ExecutionPolicy Bypass -File scripts\make_desktop_shortcut.ps1
$ErrorActionPreference = 'Stop'

$repo    = Split-Path -Parent $PSScriptRoot
$launch  = Join-Path $repo 'launch.py'
$desktop = [Environment]::GetFolderPath('Desktop')
$lnk     = Join-Path $desktop 'OpenLab Recorder.lnk'

$python = (Get-Command python.exe -ErrorAction SilentlyContinue).Source
if (-not $python) { throw 'python.exe not found on PATH. Install Python or add it to PATH.' }

$icon = Get-ChildItem -Path (Join-Path $repo 'vendor\LabRecorder') -Recurse -Filter 'LabRecorder.exe' -ErrorAction SilentlyContinue | Select-Object -First 1

$shell = New-Object -ComObject WScript.Shell
$s = $shell.CreateShortcut($lnk)
$s.TargetPath       = $python
$s.Arguments        = '"' + $launch + '"'
$s.WorkingDirectory = $repo
$s.Description       = 'Stream OpenBCI to LabRecorder over Lab Streaming Layer'
if ($icon) { $s.IconLocation = $icon.FullName + ',0' }
$s.Save()

Write-Host "Created shortcut: $lnk"
Write-Host "Icon source: $(if ($icon) { $icon.FullName } else { 'default' })"
