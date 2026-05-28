# install_windows.ps1 — one-click Windows installer for OpenLab Recorder.
#
# Called by INSTALL.bat in the repo root (which sets ExecutionPolicy Bypass).
# Can also be run directly:
#     powershell -ExecutionPolicy Bypass -File scripts\install_windows.ps1
#
# What it does:
#   1. Verify winget is available (Windows 10 1809+ / Windows 11 — ships by
#      default on modern builds; user updates App Installer if missing).
#   2. Install Python 3.12 via winget if no python launcher / python.exe found.
#   3. Refresh PATH for the current process so the just-installed python is
#      visible without restarting.
#   4. Run install.py to pip-install brainflow / pylsl / pyserial / pyxdf and
#      download LabRecorder 1.17.0 into vendor/.
#   5. Run make_desktop_shortcut.ps1 to create the Desktop icon.
#
# Does NOT require Administrator — winget can install Python per-user, pip
# install --user works, and Desktop shortcut creation is per-user. The script
# will explicitly --scope user wherever applicable.

$ErrorActionPreference = "Stop"

function Write-Info  { param($Msg) Write-Host "[+] $Msg" -ForegroundColor Green }
function Write-Warn  { param($Msg) Write-Host "[~] $Msg" -ForegroundColor Yellow }
function Write-Err   { param($Msg) Write-Host "[!] $Msg" -ForegroundColor Red }

$Repo = Split-Path -Parent $PSScriptRoot
Set-Location $Repo

# ---------- 1. winget availability ----------
$winget = Get-Command winget -ErrorAction SilentlyContinue
if (-not $winget) {
    Write-Err "winget is not installed."
    Write-Err "On Windows 10 / 11 it ships with 'App Installer' from the Microsoft Store."
    Write-Err "Open Microsoft Store, search 'App Installer', install or update it,"
    Write-Err "then re-run INSTALL.bat."
    exit 2
}
Write-Info "winget present: $((winget --version 2>$null))"

# ---------- 2. Python detection / install ----------
function Get-Python {
    $cmd = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cmd = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$python = Get-Python
if (-not $python) {
    Write-Info "Python not found. Installing Python 3.12 via winget (user scope)..."
    # --scope user avoids needing Admin; --silent skips installer UI; --accept-source-agreements + --accept-package-agreements skip prompts
    winget install --id Python.Python.3.12 --scope user --silent --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "winget Python install returned $LASTEXITCODE. Retrying without --scope user (some hosts reject user-scope MSI)..."
        winget install --id Python.Python.3.12 --silent --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) {
            Write-Err "winget Python install failed twice. Install Python manually from https://www.python.org/downloads/windows/ then re-run."
            exit 3
        }
    }

    # Refresh PATH in this process so the just-installed Python is visible.
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath    = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path    = "$machinePath;$userPath"

    $python = Get-Python
    if (-not $python) {
        Write-Err "Python installed but still not on PATH for this shell."
        Write-Err "Close this window, open a fresh PowerShell, and re-run INSTALL.bat."
        exit 4
    }
}
Write-Info "Python: $python ($((& $python --version) 2>&1))"

# ---------- 3. pip self-upgrade (avoids 'pip 2x.x is available' noise during install.py) ----------
Write-Info "Upgrading pip..."
& $python -m pip install --quiet --upgrade pip
if ($LASTEXITCODE -ne 0) {
    Write-Warn "pip self-upgrade returned $LASTEXITCODE. Continuing — pip is probably fine."
}

# ---------- 4. install.py ----------
Write-Info "Running install.py (pip dependencies + LabRecorder download)..."
& $python (Join-Path $Repo "install.py")
if ($LASTEXITCODE -ne 0) {
    Write-Err "install.py exited with $LASTEXITCODE."
    Write-Err "Common causes:"
    Write-Err "  - No network access to github.com (corporate proxy / firewall)."
    Write-Err "  - pip can't reach pypi.org."
    Write-Err "  - brainflow wheel unavailable for your Python version (try Python 3.11 or 3.12)."
    Write-Err "Re-run from a fresh PowerShell once the cause is addressed."
    exit 5
}

# ---------- 5. Desktop shortcut ----------
Write-Info "Creating Desktop shortcut..."
$shortcutScript = Join-Path $Repo "scripts\make_desktop_shortcut.ps1"
if (Test-Path $shortcutScript) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $shortcutScript
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Desktop shortcut creation failed ($LASTEXITCODE). The install itself succeeded — you can run launch.py directly."
    }
} else {
    Write-Warn "scripts\make_desktop_shortcut.ps1 not found — skipping Desktop shortcut step."
}

Write-Info ""
Write-Info "=================================================================="
Write-Info "  OpenLab Recorder install complete."
Write-Info "  Look on your Desktop for the 'OpenLab Recorder' icon."
Write-Info "  Double-click it. It will:"
Write-Info "    - auto-detect the OpenBCI dongle COM port"
Write-Info "    - open LabRecorder"
Write-Info "    - start the bridge"
Write-Info "  Then in LabRecorder pick 'OpenBCI_EEG' and press Start."
Write-Info "=================================================================="
exit 0
