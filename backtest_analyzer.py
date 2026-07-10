#!/usr/bin/env python3
"""
Backtest error code analyzer.
Extracts and counts RETRY:* error codes from MT5 logs using ASCII-safe output.
"""

import re
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path


def status_for_count(count):
    if 15 < count < 100:
        return "[OK]"
    if count > 100:
        return "[WARN]"
    return "[INFO]"


def read_text_file(path):
    data = path.read_bytes()
    if data.startswith(b"\xff\xfe") or data.startswith(b"\xfe\xff"):
        return data.decode("utf-16", errors="ignore")

    for encoding in ("utf-8", "utf-16", "cp1252", "latin-1"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue

    return data.decode("utf-8", errors="ignore")


def analyze_backtest_log(log_file_path):
    log_path = Path(log_file_path)
    if not log_path.exists():
        print(f"[FAIL] Log file not found: {log_path}")
        return 1

    error_codes = defaultdict(int)
    total_lines = 0
    trades_executed = 0

    print("\n" + "=" * 70)
    print("BACKTEST ERROR CODE ANALYSIS")
    print("=" * 70)
    print(f"Log File: {log_path}")
    print(f"Analysis Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 70 + "\n")

    try:
        content = read_text_file(log_path)
    except OSError as exc:
        print(f"[FAIL] Error reading log file: {exc}")
        return 1

    for line in content.splitlines():
        total_lines += 1
        lowered = line.lower()

        if "deal" in lowered or "order" in lowered:
            trades_executed += 1

        for match in re.findall(r"RETRY:([A-Za-z0-9_]+)", line):
            error_codes[f"RETRY:{match}"] += 1

    if error_codes:
        print("ERROR CODES FOUND:\n")
        print(f"{'Error Code':<40} {'Count':>8} {'Pct':>6}")
        print("-" * 58)

        total_errors = sum(error_codes.values())
        for code, count in sorted(error_codes.items(), key=lambda item: item[1], reverse=True):
            pct = (count / total_errors * 100.0) if total_errors else 0.0
            print(f"{status_for_count(count)} {code:<35} {count:>8} {pct:>5.1f}%")

        print("-" * 58)
        print(f"  {'TOTAL':<35} {total_errors:>8} {'100.0':>5}%\n")

        print("FIX VALIDATION:\n")
        fixes_status = {
            "RETRY:QuoteSnapshotStale": ("FIX #1", "Quote validation (stale)", (15, 30)),
            "RETRY:QuoteSnapshotDrift": ("FIX #1", "Quote validation (drift)", (5, 15)),
            "RETRY:SignalTooStaleAtExecution": ("FIX #4", "Signal age decay", (10, 25)),
            "RETRY:SymbolExposureAtPendingSend": ("FIX #2", "Position recheck", (5, 10)),
            "RETRY:PendingOrderAlreadyLive": ("FIX #3", "Duplicate prevention", (0, 5)),
        }

        for code, (fix_num, description, expected_range) in fixes_status.items():
            count = error_codes.get(code, 0)
            is_active = count > 0
            in_range = expected_range[0] <= count <= expected_range[1] if is_active else True
            status = "[OK]" if in_range else "[WARN]"
            activity = "ACTIVE" if is_active else "NOT ACTIVE"
            range_text = (
                f"(expected {expected_range[0]}-{expected_range[1]})"
                if is_active
                else "(not triggered)"
            )
            print(f"{status} {fix_num} - {description:<25} {activity:<12} {count:>4} {range_text}")
    else:
        print("[WARN] NO ERROR CODES FOUND")
        print("This may indicate:")
        print("  - Fixes are not integrated in code")
        print("  - The log file does not contain retry diagnostics")
        print("  - The backtest did not execute enough trades")

    print("\n" + "=" * 70)
    print("FILE STATISTICS")
    print("=" * 70)
    print(f"Total Lines Scanned: {total_lines:,}")
    print(f"Approx Trades Executed: {trades_executed}")
    print()
    return 0


def find_latest_backtest_log():
    workspace = Path(__file__).resolve().parent
    terminal_root = workspace.parents[2]
    log_dir = terminal_root / "logs"

    if not log_dir.exists():
        print(f"[FAIL] Logs directory not found: {log_dir}")
        return None

    log_files = list(log_dir.glob("*.log"))
    if not log_files:
        print(f"[FAIL] No log files found in: {log_dir}")
        return None

    return max(log_files, key=lambda path: path.stat().st_mtime)


if __name__ == "__main__":
    log_file = Path(sys.argv[1]) if len(sys.argv) > 1 else find_latest_backtest_log()

    if log_file is None:
        print("\nUsage: python backtest_analyzer.py [log_file_path]")
        print("If no path is provided, the latest MT5 terminal log is used.")
        sys.exit(1)

    print(f"Using log file: {log_file}\n")
    sys.exit(analyze_backtest_log(log_file))
