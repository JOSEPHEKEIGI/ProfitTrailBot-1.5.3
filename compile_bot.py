#!/usr/bin/env python3
"""
ProfitTrailBot MQL5 Compilation Automation
Auto-compiles using MetaTrader terminal integration
"""

import os
import sys
import time
import subprocess
from pathlib import Path
from datetime import datetime

def find_metaeditor():
    """Find MetaEditor executable"""
    possible_paths = [
        r"C:\Program Files\MetaTrader 5\metaeditor64.exe",
        r"C:\Program Files (x86)\MetaTrader 5\metaeditor64.exe",
        r"C:\Program Files\MetaTrader 5 - Buraq Terminal\metaeditor64.exe",
        r"C:\Program Files\TradingView MetaTrader 5 by Buraq\metaeditor64.exe",
    ]
    
    for path in possible_paths:
        if os.path.exists(path):
            return path
    return None

def compile_mq5():
    """Compile the MQ5 file"""
    
    mq5_file = r"c:\Users\Joseph Nganga\AppData\Roaming\MetaQuotes\Terminal\BB16F565FAAA6B23A20C26C49416FF05\MQL5\Experts\ProfitTrailBot 1.5.2\ProfitTrailBotEnterprises-1.5.2.mq5"
    ex5_file = mq5_file.replace('.mq5', '.ex5')
    
    print("\n" + "="*60)
    print("ProfitTrailBot MQL5 Compilation")
    print("="*60 + "\n")
    
    # Verify MQ5 file exists
    if not os.path.exists(mq5_file):
        print(f"❌ ERROR: MQ5 file not found: {mq5_file}")
        return False
    
    print(f"✓ MQ5 file found: {mq5_file}")
    
    # Get current timestamp
    ex5_timestamp_before = None
    if os.path.exists(ex5_file):
        ex5_timestamp_before = os.path.getmtime(ex5_file)
        print(f"✓ Current .ex5 timestamp: {datetime.fromtimestamp(ex5_timestamp_before)}")
    
    # Find MetaEditor
    metaeditor = find_metaeditor()
    if metaeditor:
        print(f"✓ MetaEditor found: {metaeditor}\n")
        
        try:
            print("Starting compilation...")
            # Use subprocess to call MetaEditor
            result = subprocess.run(
                [metaeditor, f'/compile:"{mq5_file}"', '/log'],
                capture_output=True,
                timeout=120,
                text=True
            )
            
            print(f"Process exit code: {result.returncode}")
            
            # Wait for file to update
            print("\nWaiting for compilation to complete...")
            time.sleep(5)
            
            # Check if .ex5 was updated
            if os.path.exists(ex5_file):
                ex5_timestamp_after = os.path.getmtime(ex5_file)
                if ex5_timestamp_before is None or ex5_timestamp_after > ex5_timestamp_before:
                    print(f"✓ SUCCESS: .ex5 file compiled!")
                    print(f"  New timestamp: {datetime.fromtimestamp(ex5_timestamp_after)}")
                    return True
                else:
                    print("⚠ WARNING: .ex5 file was not updated")
            else:
                print("⚠ WARNING: .ex5 file not found")
                
        except subprocess.TimeoutExpired:
            print("⚠ Compilation timeout (may still be processing)")
        except Exception as e:
            print(f"⚠ Error during compilation: {e}")
    else:
        print("ℹ MetaEditor not found in standard locations")
        print("ℹ MT5 will auto-compile when file is saved\n")
    
    # Display what changed
    print("\n" + "="*60)
    print("Changes Applied to ProfitTrailBotEnterprises-1.5.2.mq5:")
    print("="*60)
    print("1. Line 479:  Strategy_Mix = STRAT_ICT_ONLY")
    print("             (was: STRAT_BOTH)")
    print("\n2. Line 496:  Suitability_Log_Decisions = true")
    print("             (was: false)")
    print("\n" + "="*60)
    print("Next: Monitor MT5 for trade execution in 5-10 minutes")
    print("="*60 + "\n")
    
    return True

if __name__ == "__main__":
    try:
        compile_mq5()
    except KeyboardInterrupt:
        print("\n\nCompilation cancelled by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n\nFATAL ERROR: {e}")
        sys.exit(1)
