#!/usr/bin/env python3
"""OpenBCI Cyton / Cyton+Daisy  ->  Lab Streaming Layer outlet  ->  LabRecorder.

The OpenBCI USB dongle speaks OpenBCI's own serial protocol; it cannot emit a
Lab Streaming Layer (LSL) stream on its own, and LabRecorder only ingests LSL
streams. This script is the bridge between the two:

    OpenBCI board  --(serial/dongle)-->  BrainFlow  --(this script)-->  LSL outlet
                                                                          |
                                                          LabRecorder discovers + records to .xdf

BrainFlow opens the board over the dongle's serial port and gives us samples in
microvolts; we wrap those samples in a pylsl StreamOutlet with proper channel
metadata so LabRecorder records a well-formed Extensible Data Format (.xdf) file.

Run this script first; the outlet then appears in LabRecorder's "Record from
Streams" list. Stop with Ctrl-C.

Dependencies (NOT auto-installed): brainflow, pylsl. See requirements.txt.

Verify board IDs / channel layout against your installed BrainFlow version:
    python -c "from brainflow.board_shim import BoardIds; print(list(BoardIds))"
"""
from __future__ import annotations

import argparse
import signal
import sys
import time

from brainflow.board_shim import BoardShim, BrainFlowInputParams, BoardIds
from pylsl import StreamInfo, StreamOutlet, local_clock

# Board selection. Cyton alone = 8 channels @ 250 Hz; Cyton+Daisy = 16 ch @ 125 Hz.
BOARDS = {
    "cyton": BoardIds.CYTON_BOARD,
    "daisy": BoardIds.CYTON_DAISY_BOARD,
}

_running = True


def _stop(_signum, _frame):
    global _running
    _running = False


def build_outlet(board_id: int, stream_name: str, source_id: str) -> tuple[StreamOutlet, list[int]]:
    """Create an LSL EEG outlet whose metadata matches the board's EEG channels."""
    eeg_rows = BoardShim.get_eeg_channels(board_id)
    srate = BoardShim.get_sampling_rate(board_id)
    try:
        labels = BoardShim.get_eeg_names(board_id)  # 10-20 names for Cyton defaults
    except Exception:
        labels = [f"ch{i}" for i in range(len(eeg_rows))]
    if len(labels) != len(eeg_rows):
        labels = [f"ch{i}" for i in range(len(eeg_rows))]

    info = StreamInfo(
        name=stream_name,
        type="EEG",
        channel_count=len(eeg_rows),
        nominal_srate=float(srate),
        channel_format="float32",
        source_id=source_id,
    )
    # Channel metadata block (XDF consumers and MNE-Python read this).
    chans = info.desc().append_child("channels")
    for label in labels:
        ch = chans.append_child("channel")
        ch.append_child_value("label", label)
        ch.append_child_value("unit", "microvolts")
        ch.append_child_value("type", "EEG")
    info.desc().append_child_value("manufacturer", "OpenBCI")

    print(f"LSL outlet '{stream_name}': {len(eeg_rows)} ch @ {srate} Hz")
    print(f"  channels: {', '.join(labels)}")
    return StreamOutlet(info, chunk_size=0, max_buffered=360), eeg_rows


def stream(port: str, board_key: str, stream_name: str, source_id: str, poll_hz: float) -> int:
    board_id = BOARDS[board_key]
    params = BrainFlowInputParams()
    params.serial_port = port

    board = BoardShim(board_id, params)
    outlet, eeg_rows = build_outlet(board_id, stream_name, source_id)

    board.prepare_session()
    board.start_stream()
    print(f"Streaming from {port} ({board_key}). Open LabRecorder and record. Ctrl-C to stop.")

    period = 1.0 / poll_hz
    try:
        while _running:
            time.sleep(period)
            data = board.get_board_data()  # channels x samples; clears the ringbuffer
            if data.shape[1] == 0:
                continue
            # BrainFlow gives channels x samples in microvolts; LSL wants samples x channels.
            chunk = data[eeg_rows, :].T.tolist()
            # Single timestamp = time of the most recent sample; LSL back-dates the
            # rest of the chunk by the nominal sample rate.
            outlet.push_chunk(chunk, local_clock())
    finally:
        try:
            board.stop_stream()
        finally:
            board.release_session()
        print("\nStopped; session released.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="OpenBCI -> LSL bridge for LabRecorder")
    ap.add_argument(
        "--port", required=True,
        help="Dongle serial port. Windows e.g. COM3; Linux/WSL e.g. /dev/ttyUSB0",
    )
    ap.add_argument(
        "--board", choices=BOARDS.keys(), default="daisy",
        help="cyton (8ch/250Hz) or daisy (16ch/125Hz). Default: daisy",
    )
    ap.add_argument("--name", default="OpenBCI_EEG", help="LSL stream name shown in LabRecorder")
    ap.add_argument("--source-id", default="openbci_cyton_dongle",
                    help="Stable LSL source_id (lets LabRecorder recover the stream after a reconnect)")
    ap.add_argument("--poll-hz", type=float, default=20.0,
                    help="How often per second to pull from BrainFlow and push to LSL")
    args = ap.parse_args()

    signal.signal(signal.SIGINT, _stop)
    signal.signal(signal.SIGTERM, _stop)
    if hasattr(signal, "SIGBREAK"):  # Windows Ctrl-Break / CTRL_BREAK_EVENT
        signal.signal(signal.SIGBREAK, _stop)
    BoardShim.disable_board_logger()
    try:
        return stream(args.port, args.board, args.name, args.source_id, args.poll_hz)
    except Exception as exc:  # surface BrainFlow errors plainly
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
