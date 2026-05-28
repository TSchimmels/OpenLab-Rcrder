#!/usr/bin/env python3
"""Quick hardware probe: open the OpenBCI board, stream briefly, report shape.

Usage: python src/probe_board.py --port COM34 --board daisy
Prints EEG channel count, sample rate, samples captured, and a value snapshot.
"""
from __future__ import annotations

import argparse
import time

from brainflow.board_shim import BoardShim, BrainFlowInputParams, BoardIds

BOARDS = {"cyton": BoardIds.CYTON_BOARD, "daisy": BoardIds.CYTON_DAISY_BOARD}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", required=True)
    ap.add_argument("--board", choices=BOARDS, default="daisy")
    ap.add_argument("--secs", type=float, default=3.0)
    args = ap.parse_args()

    board_id = BOARDS[args.board]
    eeg_rows = BoardShim.get_eeg_channels(board_id)
    srate = BoardShim.get_sampling_rate(board_id)
    print(f"board={args.board} id={int(board_id)} expected_eeg_ch={len(eeg_rows)} srate={srate}")

    params = BrainFlowInputParams()
    params.serial_port = args.port
    BoardShim.disable_board_logger()
    board = BoardShim(board_id, params)
    board.prepare_session()
    board.start_stream()
    time.sleep(args.secs)
    data = board.get_board_data()
    board.stop_stream()
    board.release_session()

    print(f"captured shape (rows x samples) = {data.shape}")
    if data.shape[1]:
        eeg = data[eeg_rows, :]
        print(f"eeg block = {eeg.shape}, samples/sec ~= {data.shape[1]/args.secs:.1f}")
        print(f"ch0 first 5 (uV): {eeg[0, :5].round(2).tolist()}")
        print(f"per-ch stddev (uV): {eeg.std(axis=1).round(1).tolist()}")
    else:
        print("NO DATA captured — check dongle/board power and port.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
