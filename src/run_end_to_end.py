#!/usr/bin/env python3
"""End-to-end smoke test: board -> bridge -> LSL -> LabRecorder -> .xdf -> verify.

Spawns the OpenBCI->LSL bridge and LabRecorderCLI as subprocesses, records for a
fixed duration, tears both down, then loads the resulting .xdf and prints a
summary. Windows-side so the bridge's LSL outlet and LabRecorder share a host.

Usage: python src/run_end_to_end.py --port COM34 --board daisy --secs 8
"""
from __future__ import annotations

import argparse
import signal
import subprocess
import sys
import time
from pathlib import Path

from pylsl import resolve_streams

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
BRIDGE = HERE / "openbci_lsl_bridge.py"
CLI = ROOT / "vendor" / "LabRecorder" / "LabRecorder-1.17.0-Win_amd64" / "LabRecorderCLI.exe"
REC_DIR = ROOT / "recordings"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", required=True)
    ap.add_argument("--board", default="daisy")
    ap.add_argument("--secs", type=float, default=8.0)
    args = ap.parse_args()

    REC_DIR.mkdir(exist_ok=True)
    xdf = REC_DIR / "smoketest_openbci.xdf"
    if xdf.exists():
        xdf.unlink()

    print(f"[1/5] starting bridge on {args.port} ({args.board}) ...")
    bridge = subprocess.Popen(
        [sys.executable, str(BRIDGE), "--port", args.port, "--board", args.board],
        creationflags=subprocess.CREATE_NEW_PROCESS_GROUP,
    )
    try:
        # Wait for the outlet to appear.
        deadline = time.time() + 15
        found = None
        while time.time() < deadline:
            for s in resolve_streams(wait_time=1.0):
                if s.type() == "EEG" and s.name() == "OpenBCI_EEG":
                    found = s
                    break
            if found:
                break
        if not found:
            print("ERROR: LSL outlet 'OpenBCI_EEG' never appeared.")
            return 1
        print(f"[2/5] LSL outlet up: name={found.name()} type={found.type()} "
              f"ch={found.channel_count()} srate={found.nominal_srate()}")

        print(f"[3/5] recording {args.secs}s with LabRecorderCLI -> {xdf.name}")
        rec = subprocess.Popen(
            [str(CLI), str(xdf), 'type="EEG"'],
            stdin=subprocess.PIPE, text=True,
        )
        time.sleep(args.secs)

        print("[4/5] stopping recorder (Enter) + bridge ...")
        # LabRecorderCLI quits gracefully on a newline and flushes buffered samples.
        try:
            rec.stdin.write("\n")
            rec.stdin.flush()
            rec.stdin.close()
        except Exception:
            pass
        try:
            rec.wait(timeout=10)
        except subprocess.TimeoutExpired:
            rec.terminate()
    finally:
        bridge.send_signal(signal.CTRL_BREAK_EVENT)
        try:
            bridge.wait(timeout=5)
        except subprocess.TimeoutExpired:
            bridge.terminate()

    # Verify the recording.
    print("[5/5] verifying .xdf ...")
    if not xdf.exists() or xdf.stat().st_size == 0:
        print(f"ERROR: no/empty xdf at {xdf}")
        return 1
    import pyxdf

    streams, _ = pyxdf.load_xdf(str(xdf))
    ok = False
    for s in streams:
        info = s["info"]
        ts = s["time_series"]
        n = len(ts) if not hasattr(ts, "shape") else ts.shape[0]
        nch = int(info["channel_count"][0])
        srate = info["nominal_srate"][0]
        labels = []
        try:
            chans = info["desc"][0]["channels"][0]["channel"]
            labels = [c["label"][0] for c in chans]
        except Exception:
            pass
        print(f"  stream '{info['name'][0]}' type={info['type'][0]} "
              f"ch={nch} srate={srate} samples={n}")
        if labels:
            print(f"    channels: {', '.join(labels)}")
        if info["type"][0] == "EEG" and n > 0:
            ok = True
    print(f"\nRESULT: {'PASS' if ok else 'FAIL'} — "
          f"{xdf} ({xdf.stat().st_size} bytes)")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
