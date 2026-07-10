#!/usr/bin/env python3
"""
Pre-backtest verification script for the current workspace.
Uses only ASCII output so it works on default Windows consoles.
"""

from datetime import datetime
from pathlib import Path
import sys


def mark(ok):
    return "[OK]" if ok else "[FAIL]"


def warn():
    return "[WARN]"


def print_header(title):
    print("\n" + "=" * 70)
    print(title)
    print("=" * 70)


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


def check_file_exists(path, name):
    if path.exists():
        size_kb = path.stat().st_size / 1024.0
        print(f"{mark(True)} {name:<40} {size_kb:>8.1f} KB")
        return True
    print(f"{mark(False)} {name:<40} NOT FOUND")
    return False


def check_string_in_file(file_path, search_string, description):
    try:
        content = read_text_file(file_path)
    except OSError as exc:
        print(f"{mark(False)} {description} - ERROR: {exc}")
        return False

    if search_string in content:
        print(f"{mark(True)} {description}")
        return True

    print(f"{mark(False)} {description} - NOT FOUND")
    return False


def find_main_ea(base_path):
    matches = sorted(base_path.glob("ProfitTrailBotEnterprises-*.mq5"))
    return matches[-1] if matches else None


def find_compile_log(base_path):
    preferred = [
        base_path / "compile_latest.log",
        base_path / "compile_verify.log",
        base_path / "compile_after_fix.log",
    ]
    for candidate in preferred:
        if candidate.exists():
            return candidate

    dated_logs = sorted(base_path.glob("compile*.log"), key=lambda p: p.stat().st_mtime, reverse=True)
    return dated_logs[0] if dated_logs else None


def find_latest_source_mtime(base_path):
    latest = 0.0
    for pattern in ("*.mq5", "*.mqh"):
        for path in base_path.glob(pattern):
            latest = max(latest, path.stat().st_mtime)
    return latest


def find_matching_compile_status(base_path, main_file):
    candidates = []

    compile_log = find_compile_log(base_path)
    if compile_log is not None:
        candidates.append(compile_log)

    metaeditor_log = base_path.parents[2] / "logs" / "metaeditor.log"
    if metaeditor_log.exists():
        candidates.append(metaeditor_log)

    for candidate in candidates:
        try:
            content = read_text_file(candidate)
        except OSError:
            continue

        matching_lines = [
            line.strip()
            for line in content.splitlines()
            if main_file.name in line and "compile" in line.lower()
        ]
        if not matching_lines:
            continue

        last_line = matching_lines[-1]
        compile_time = None
        if candidate.name.lower() == "metaeditor.log":
            parts = last_line.split("\t")
            if len(parts) >= 2:
                try:
                    compile_time = datetime.strptime(parts[1], "%Y.%m.%d %H:%M:%S.%f").timestamp()
                except ValueError:
                    compile_time = None

        return candidate, last_line, compile_time

    return None, None, None


def main():
    base_path = Path(__file__).resolve().parent
    main_file = find_main_ea(base_path)
    trade_file = base_path / "TradeManagement.mqh"
    analyzer_file = base_path / "backtest_analyzer.py"
    verify_file = base_path / "verify_backtest_ready.py"

    print_header("PRE-BACKTEST VERIFICATION CHECKLIST")
    print(f"Workspace: {base_path}")

    all_pass = True

    print_header("PHASE 1: FILES VERIFICATION")
    files_to_check = [
        (main_file, "Main EA File"),
        (trade_file, "Trade Engine Module"),
        (analyzer_file, "Analysis Tool"),
        (verify_file, "Verification Tool"),
    ]

    for path, name in files_to_check:
        if path is None or not check_file_exists(path, name):
            all_pass = False

    if main_file is None:
        print(f"{mark(False)} Could not locate ProfitTrailBotEnterprises-*.mq5")
        return 1

    print_header("PHASE 2: CODE VERIFICATION")
    fixes_to_check = [
        (main_file, "enum ENUM_SIGNAL_ORIGIN", "Enum: Signal Origin"),
        (main_file, "struct STradingSignal", "Struct: Trading Signal"),
        (trade_file, "GetSymbolFillingMode", "Trade filling resolver"),
        (trade_file, "ComputeSignalFingerprint", "Signal fingerprinting"),
        (trade_file, "CleanupExpiredPendingOrders", "Pending-order cleanup"),
        (trade_file, "RunBrokerExecutionPreflight", "Broker execution preflight"),
    ]

    for file_path, search_str, desc in fixes_to_check:
        if not check_string_in_file(file_path, search_str, desc):
            all_pass = False

    print_header("PHASE 3: COMPILATION STATUS")
    log_file, compile_line, compile_time = find_matching_compile_status(base_path, main_file)
    if log_file is None or compile_line is None:
        print(f"{warn()} No compile record found for {main_file.name}")
        all_pass = False
    else:
        print(f"Using compile source: {log_file.name}")
        latest_source_mtime = find_latest_source_mtime(base_path)
        clean_compile = ("0 errors" in compile_line.lower() and "0 warnings" in compile_line.lower())
        stale_compile = (compile_time is not None and compile_time < latest_source_mtime)

        if clean_compile and not stale_compile:
            print(f"{mark(True)} Latest matching compile shows 0 errors, 0 warnings")
        elif clean_compile and stale_compile:
            print(f"{warn()} Matching compile was clean, but it is older than current source files")
            print(f"  {compile_line}")
            all_pass = False
        else:
            print(f"{warn()} Latest matching compile result:")
            print(f"  {compile_line}")
            all_pass = False

    print_header("PHASE 4: RECOMMENDED TESTER CONFIGURATION")
    config = {
        "Expert Advisor": main_file.stem,
        "Symbol": "XAUUSD or GOLD",
        "Period": "M15",
        "Model": "Every tick",
        "Visualization": "OFF unless debugging entries",
        "Post-run analysis": "python backtest_analyzer.py [optional_log_path]",
    }
    for setting, value in config.items():
        print(f"  {setting:<22} -> {value}")

    print("\n" + "=" * 70)
    if all_pass:
        print("[OK] ALL CHECKS PASSED - READY FOR BACKTEST")
        print("=" * 70)
        print("Next steps:")
        print("1. Compile the EA in MetaEditor if you changed code since the last compile log.")
        print("2. Run the Strategy Tester with the configuration above.")
        print("3. Run: python backtest_analyzer.py")
        return 0

    print("[FAIL] SOME CHECKS FAILED - REVIEW ABOVE")
    print("=" * 70)
    print("Action required:")
    print("- Fix the missing or outdated items above.")
    print("- Recompile in MT5 and refresh the compile log.")
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"\n[FAIL] Error during verification: {exc}\n")
        sys.exit(1)
