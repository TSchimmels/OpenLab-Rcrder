#!/usr/bin/env python3
"""One-click launcher for OpenLab Recorder (target of the desktop icon).

Auto-detects the OpenBCI dongle's serial port, opens LabRecorder, and starts the
bridge in this console window. Close the window (or Ctrl-C) to stop streaming.

    python launch.py            # board defaults to daisy (Cyton+Daisy, 16 ch)
    python launch.py cyton      # 8-channel Cyton
"""
from __future__ import annotations

import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
BRIDGE = HERE / "src" / "openbci_lsl_bridge.py"
LABRECORDER = next((HERE / "vendor" / "LabRecorder").rglob("LabRecorder.exe"), None)

FTDI_VID = 0x0403  # OpenBCI dongle uses an FTDI USB-serial chip


def find_dongle_port() -> str | None:
    try:
        from serial.tools import list_ports
    except ImportError:
        print("pyserial not installed — run: python install.py  (or pip install pyserial)")
        return None
    ports = list(list_ports.comports())
    for p in ports:  # prefer the FTDI dongle
        if p.vid == FTDI_VID:
            return p.device
    for p in ports:  # otherwise first USB serial device
        if "USB" in (p.description or "") or "Serial" in (p.description or ""):
            return p.device
    return ports[0].device if ports else None


def main() -> int:
    board = sys.argv[1] if len(sys.argv) > 1 else "daisy"
    port = find_dongle_port()
    if not port:
        print("No serial dongle found. Plug in the OpenBCI dongle and re-run.")
        input("Press Enter to close...")
        return 1
    print(f"OpenBCI dongle: {port}  |  board: {board}")

    if LABRECORDER:
        print(f"Opening LabRecorder: {LABRECORDER.name}")
        subprocess.Popen([str(LABRECORDER)])
        time.sleep(1.0)
    else:
        print("LabRecorder not found in vendor/ — run: python install.py")

    print("Starting stream. In LabRecorder, click Update, check 'OpenBCI_EEG', then Start.")
    print("Close this window or press Ctrl-C to stop streaming.\n")
    return subprocess.call([sys.executable, str(BRIDGE), "--port", port, "--board", board])


if __name__ == "__main__":
    raise SystemExit(main())
