#!/usr/bin/env bash
# install_macos.sh — one-click macOS installer for OpenLab Recorder.
#
# Called by INSTALL_macOS.command at the repo root. Can also be run directly:
#     bash scripts/install_macos.sh
#
# Why each step exists:
#
#   1. Homebrew — macOS has no built-in package manager. brew is the de facto
#      standard for installing python@3.12 and liblsl. Apple Silicon installs
#      to /opt/homebrew, Intel to /usr/local — handled below.
#
#   2. Python 3.12 — modern macOS ships /usr/bin/python3 only after Xcode
#      Command Line Tools is installed (and it's older). brew install
#      python@3.12 is the reliable path. Pinned to 3.12 because brainflow's
#      wheel coverage for 3.13 may lag on macOS arm64.
#
#   3. liblsl — pylsl on macOS is the silent failure: `pip install pylsl`
#      succeeds, but `import pylsl` throws because liblsl.dylib isn't found.
#      The labstreaminglayer org's brew tap (labstreaminglayer/tap/lsl) is
#      the standard install path. UNVERIFIED against the live brew tap
#      this session — if `brew install labstreaminglayer/tap/lsl` fails,
#      falls back to suggesting the conda-forge path.
#
#   4. install.py — pip deps + LabRecorder download (existing repo script).
#
#   5. Gatekeeper quarantine strip — macOS quarantines any file downloaded
#      from a browser / curl / urlretrieve with the com.apple.quarantine
#      extended attribute. Trying to launch the LabRecorder binary then
#      triggers "cannot be opened because the developer cannot be verified."
#      `xattr -d -r com.apple.quarantine <path>` removes the attribute.
#      This is the canonical Gatekeeper bypass for user-trusted downloads.
#
#   6. Desktop alias — macOS equivalent of the Windows .lnk shortcut.
#      Uses osascript to make a Finder alias since `ln -s` puts a unix
#      symlink that Finder treats oddly.

set -euo pipefail

err()  { printf '[!] %s\n' "$*" >&2; }
ok()   { printf '[+] %s\n' "$*"; }
warn() { printf '[~] %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---------- 0. Sanity ----------
if [[ "$(uname -s)" != "Darwin" ]]; then
  err "This installer is for macOS. uname -s reports: $(uname -s)"
  err "On Windows use INSTALL.bat. On Linux see the README for manual install."
  exit 1
fi

ARCH="$(uname -m)"
MACOS_VER="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
ok "macOS ${MACOS_VER} (arch: ${ARCH})"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

# ---------- 1. Homebrew ----------
if have brew; then
  ok "Homebrew already installed: $(brew --version | head -1)"
else
  ok "Installing Homebrew (will prompt for your macOS password)..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Make brew available in this shell without opening a new terminal
  if [[ "${ARCH}" == "arm64" ]] && [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  if ! have brew; then
    err "Homebrew install completed but brew is not on PATH for this shell."
    err "Quit Terminal, reopen it, and re-run INSTALL_macOS.command."
    exit 2
  fi
fi

# ---------- 2. Python 3.12 ----------
if have python3.12; then
  PYTHON="$(command -v python3.12)"
  ok "python3.12 already installed: $PYTHON ($(python3.12 --version))"
else
  ok "Installing python@3.12 via Homebrew..."
  brew install python@3.12
  # brew install python doesn't always symlink python3.12 onto PATH cleanly;
  # use the brew --prefix path explicitly.
  BREW_PY="$(brew --prefix python@3.12)/bin/python3.12"
  if [[ -x "$BREW_PY" ]]; then
    PYTHON="$BREW_PY"
    ok "python3.12 installed at: $PYTHON"
  elif have python3; then
    PYTHON="$(command -v python3)"
    warn "python3.12 not on PATH; falling back to $PYTHON ($(python3 --version))"
  else
    err "Python install completed but no python3.12 / python3 on PATH."
    err "Quit Terminal, reopen it, and re-run INSTALL_macOS.command."
    exit 3
  fi
fi

# ---------- 3. liblsl ----------
# pylsl on macOS NEEDS liblsl installed separately. This is the most likely
# cause of the "install fails on macOS but Windows is fine" pattern.
if [[ -f "$(brew --prefix)/lib/liblsl.dylib" ]] || [[ -f /usr/local/lib/liblsl.dylib ]] || [[ -f /opt/homebrew/lib/liblsl.dylib ]]; then
  ok "liblsl already installed (found liblsl.dylib in brew prefix)"
else
  ok "Installing liblsl via labstreaminglayer/tap..."
  if brew install labstreaminglayer/tap/lsl 2>&1 | tail -5; then
    ok "liblsl installed via brew tap."
  else
    warn "brew install labstreaminglayer/tap/lsl failed."
    warn "Fallback paths to try manually:"
    warn "    conda install -c conda-forge liblsl   (if you have conda/miniforge)"
    warn "    Download liblsl from https://github.com/sccn/liblsl/releases"
    warn "Continuing — pylsl pip wheel will install but `import pylsl` will fail at runtime."
  fi
fi

# ---------- 4. install.py ----------
ok "Running install.py (pip deps + LabRecorder download)..."
"$PYTHON" -m pip install --quiet --upgrade pip
"$PYTHON" "$REPO/install.py"

# ---------- 5. Gatekeeper quarantine strip on the downloaded LabRecorder ----------
VENDOR="$REPO/vendor/LabRecorder"
if [[ -d "$VENDOR" ]]; then
  ok "Stripping macOS Gatekeeper quarantine on downloaded LabRecorder..."
  # -r recursive, -d delete; ignores files that don't have the attribute
  xattr -dr com.apple.quarantine "$VENDOR" 2>/dev/null || true
  ok "Quarantine cleared. LabRecorder will launch without 'unidentified developer' block."
else
  warn "vendor/LabRecorder not found after install.py — Gatekeeper strip skipped."
fi

# ---------- 6. Desktop alias ----------
DESKTOP="$HOME/Desktop"
LAUNCH_PY="$REPO/launch.py"
ALIAS_PATH="$DESKTOP/OpenLab Recorder.command"

if [[ -f "$LAUNCH_PY" ]]; then
  ok "Creating Desktop launcher (OpenLab Recorder.command)..."
  cat > "$ALIAS_PATH" <<EOF
#!/bin/bash
# Launches OpenLab Recorder: auto-detects OpenBCI dongle, opens LabRecorder, starts bridge.
cd "$REPO"
"$PYTHON" "$LAUNCH_PY"
EOF
  chmod +x "$ALIAS_PATH"
  ok "Desktop launcher: $ALIAS_PATH"
else
  warn "launch.py not found at $LAUNCH_PY — Desktop launcher skipped."
fi

echo
ok "=================================================================="
ok "  OpenLab Recorder install complete."
ok "  Double-click 'OpenLab Recorder.command' on your Desktop."
ok "  It will:"
ok "    - auto-detect the OpenBCI dongle serial port"
ok "    - open LabRecorder"
ok "    - start the bridge"
ok "  In LabRecorder, pick 'OpenBCI_EEG' and press Start."
ok "=================================================================="
ok ""
ok "First-time-only note: macOS may show one Gatekeeper warning the very"
ok "first time you run the Desktop launcher. Right-click it -> Open ->"
ok "Open (instead of double-click). After that double-click works normally."
exit 0
