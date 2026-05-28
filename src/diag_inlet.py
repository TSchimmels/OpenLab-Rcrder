#!/usr/bin/env python3
"""Diagnostic: spawn the bridge, pull from its LSL outlet with an inlet, count.

Tells us whether board->LSL actually pushes samples (isolating the recorder).
"""
from __future__ import annotations

import argparse
import signal
import subprocess
import sys
import time
from pathlib import Path

from pylsl import resolve_streams, StreamInlet

HERE = Path(__file__).resolve().parent
BRIDGE = HERE / "openbci_lsl_bridge.py"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", required=True)
    ap.add_argument("--board", default="daisy")
    ap.add_argument("--secs", type=float, default=5.0)
    args = ap.parse_args()

    bridge = subprocess.Popen(
        [sys.executable, str(BRIDGE), "--port", args.port, "--board", args.board],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        creationflags=subprocess.CREATE_NEW_PROCESS_GROUP,
    )
    total = 0
    first = None
    try:
        found = None
        deadline = time.time() + 15
        while time.time() < deadline and not found:
            for s in resolve_streams(wait_time=1.0):
                if s.name() == "OpenBCI_EEG":
                    found = s
                    break
        if not found:
            print("no outlet found")
            return 1
        inlet = StreamInlet(found, max_buflen=60)
        t_end = time.time() + args.secs
        while time.time() < t_end:
            chunk, stamps = inlet.pull_chunk(timeout=1.0, max_samples=1024)
            if stamps:
                total += len(stamps)
                if first is None:
                    first = (chunk[0][:4], stamps[0])
    finally:
        bridge.send_signal(signal.CTRL_BREAK_EVENT)
        try:
            out, _ = bridge.communicate(timeout=6)
        except subprocess.TimeoutExpired:
            bridge.terminate()
            out, _ = bridge.communicate()

    print(f"PULLED {total} samples in {args.secs}s  (~{total/args.secs:.1f}/s)")
    if first:
        print(f"first sample ch0-3: {[round(v,2) for v in first[0]]}  stamp={first[1]:.3f}")
    print("---- bridge stdout/stderr ----")
    print(out)
    return 0 if total > 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
