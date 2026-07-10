#!/usr/bin/env python3
"""
Real-Time Backtest Progress Monitor
Run this every 30 minutes during backtest to check progress
Usage: python backtest_progress_monitor.py
"""

import os
import sys
import time
from pathlib import Path
from datetime import datetime

def get_latest_log():
    """Find the most recent backtest log file"""
    log_dir = r"C:\Users\Joseph Nganga\AppData\Roaming\MetaQuotes\Terminal\BB16F565FAAA6B23A20C26C49416FF05\logs"
    
    if not Path(log_dir).exists():
        return None
    
    log_files = list(Path(log_dir).glob("*.log"))
    if not log_files:
        return None
    
    # Return most recent
    return max(log_files, key=lambda p: p.stat().st_mtime)

def get_deal_count(log_file):
    """Extract deal count from log"""
    if not log_file or not log_file.exists():
        return 0
    
    try:
        with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
            line_count = 0
            deal_keywords = ['deal', 'order', 'trade', 'executed']
            for line in f:
                line_lower = line.lower()
                if any(keyword in line_lower for keyword in deal_keywords):
                    line_count += 1
            return line_count
    except:
        return 0

def get_file_size_mb(file_path):
    """Get file size in MB"""
    if Path(file_path).exists():
        return Path(file_path).stat().st_size / (1024 * 1024)
    return 0

def main():
    print("\n" + "="*70)
    print("BACKTEST PROGRESS MONITOR")
    print(f"Checked at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("="*70 + "\n")
    
    log_file = get_latest_log()
    
    if not log_file:
        print("⚠ No backtest log found yet")
        print("   (Backtest may not have started or logs directory issue)")
        print("\n" + "="*70 + "\n")
        return
    
    print(f"Log File: {log_file.name}")
    print(f"Size: {get_file_size_mb(log_file):.2f} MB")
    print(f"Modified: {datetime.fromtimestamp(log_file.stat().st_mtime).strftime('%Y-%m-%d %H:%M:%S')}")
    
    # === CHECK LOG CONTENT ===
    with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()
    
    print(f"Lines in log: {len(lines):,}")
    
    # === EXTRACT STATUS ===
    print("\n" + "-"*70)
    print("BACKTEST STATUS")
    print("-"*70)
    
    error_count = sum(1 for line in lines if 'error' in line.lower())
    warning_count = sum(1 for line in lines if 'warning' in line.lower())
    deal_count = get_deal_count(log_file)
    
    print(f"Errors detected: {error_count}")
    print(f"Warnings detected: {warning_count}")
    print(f"Approx Deals/Trades: ~{deal_count}")
    
    # === CHECK FOR FIX ERROR CODES ===
    print("\n" + "-"*70)
    print("FIX ERROR CODES DETECTED")
    print("-"*70)
    
    fix_codes = {
        'RETRY:QuoteSnapshotStale': 'FIX #1 (Quote validation - stale)',
        'RETRY:QuoteSnapshotDrift': 'FIX #1 (Quote validation - drift)',
        'RETRY:SignalTooStaleAtExecution': 'FIX #4 (Signal age decay)',
        'RETRY:SymbolExposureAtPendingSend': 'FIX #2 (Position recheck)',
        'RETRY:PendingOrderAlreadyLive': 'FIX #3 (Duplicate prevention)',
    }
    
    code_counts = {}
    for line in lines:
        for code, desc in fix_codes.items():
            if code in line:
                code_counts[code] = code_counts.get(code, 0) + 1
    
    if code_counts:
        total_codes = sum(code_counts.values())
        print(f"\nTotal fix codes found: {total_codes}\n")
        
        for code, count in sorted(code_counts.items(), key=lambda x: x[1], reverse=True):
            desc = fix_codes[code]
            status = "✓" if count > 0 else "~"
            print(f"{status} {code:<35} {count:>4} occurrences")
    else:
        print("⚠ No fix error codes found yet")
        print("  (May appear later in backtest or if fixes not triggering)")
    
    # === CRITICAL ISSUES ===
    print("\n" + "-"*70)
    print("CRITICAL ISSUES CHECK")
    print("-"*70)
    
    critical_keywords = [
        'OrderSend failed',
        'initialization failed',
        'access violation',
        'abnormally terminated',
        'memory error'
    ]
    
    critical_found = False
    for keyword in critical_keywords:
        if sum(1 for line in lines if keyword.lower() in line.lower()) > 0:
            print(f"⚠ {keyword} - FOUND {sum(1 for line in lines if keyword.lower() in line.lower())} times")
            critical_found = True
    
    if not critical_found:
        print("✓ No critical errors detected")
    
    # === RECOMMENDATIONS ===
    print("\n" + "-"*70)
    print("RECOMMENDATIONS")
    print("-"*70)
    
    if deal_count < 10 and len(lines) > 1000:
        print("⚠ Very few trades generated - backtest may have issues")
    elif deal_count > 500 and len(lines) > 10000:
        print("✓ Backtest progressing well - many trades generated")
    else:
        print(f"⚠ Backtest in progress - {deal_count} trades so far")
    
    if error_count > 100:
        print("⚠ Many errors in log - check details")
    elif error_count > 0:
        print("⚠ Some errors present - may be recoverable")
    else:
        print("✓ No errors detected")
    
    if code_counts and total_codes > 40:
        print("✓ Fixes are triggering (good indicator)")
    elif code_counts and total_codes > 0:
        print("⚠ Fixes triggering but not frequently")
    else:
        print("⚠ Fixes not triggering yet (check later)")
    
    print("\n" + "="*70)
    print("STATUS: BACKTEST IN PROGRESS - Check again in 30 minutes")
    print("="*70 + "\n")

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"\n✗ Error during monitoring: {e}\n")
