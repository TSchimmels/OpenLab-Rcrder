#!/bin/bash
# ============================================================================
#  OpenLab Recorder — one-click macOS installer.
#  Double-click this file in Finder. macOS opens Terminal and runs it.
#  That's it.
#
#  What it does (calls scripts/install_macos.sh which holds the real logic):
#    1. Installs Homebrew if missing.
#    2. brew install python@3.12 + the liblsl native library
#       (pylsl on macOS needs liblsl separately — pip alone is not enough).
#    3. Runs install.py (pip deps + LabRecorder download into vendor/).
#    4. Strips macOS Gatekeeper quarantine on the downloaded LabRecorder
#       binary so it actually launches without "unidentified developer" block.
#    5. Creates an "OpenLab Recorder" alias on the Desktop.
#
#  The window stays open at the end so you can read any error output.
# ============================================================================

set -e

# Resolve repo dir even if user double-clicked from Finder (cwd may be $HOME)
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO"

echo "[+] OpenLab Recorder — macOS installer"
echo "[+] Repo: $REPO"
echo

bash "$REPO/scripts/install_macos.sh"
EXITCODE=$?

echo
if [ $EXITCODE -eq 0 ]; then
  echo "[SUCCESS] OpenLab Recorder installed. Look on your Desktop for the icon."
else
  echo "[ERROR] Installer exited with code $EXITCODE. Scroll up to see what went wrong."
fi
echo
echo "Press Enter to close this window..."
read -r _
exit $EXITCODE
