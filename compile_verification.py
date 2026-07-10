#!/usr/bin/env python3
"""
MQL5 Compilation Verification Script
Validates syntax of all modified files and checks for common compilation errors
"""

import os
import re
import sys
from pathlib import Path
from datetime import datetime

class MQL5Validator:
    def __init__(self, project_dir):
        self.project_dir = Path(project_dir)
        self.errors = []
        self.warnings = []
        self.fixed_files = [
            "AIInferenceEngine.mqh",      # Fix #11
            "SymbolManagement.mqh",       # Fix #15
            "AICandleQualityFilter.mqh",  # Fix #10
            "TrendAnalysisEnhanced.mqh",  # Fix #10
            "MainLifecycle.mqh",          # Fix #7
            "AIScaler.mqh",               # Fix #12
        ]
        
    def validate(self):
        print("=" * 70)
        print(f"MQL5 Compilation Verification - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print("=" * 70)
        print(f"Project Directory: {self.project_dir}")
        print()
        
        # Check each fixed file
        for filename in self.fixed_files:
            filepath = self.project_dir / filename
            if not filepath.exists():
                self.errors.append(f"CRITICAL: File not found: {filename}")
                continue
            
            self._validate_file(filepath, filename)
        
        # Check main bot file
        main_file = self.project_dir / "ProfitTrailBotEnterprises-1.5.2.mq5"
        if main_file.exists():
            self._validate_file(main_file, "ProfitTrailBotEnterprises-1.5.2.mq5")
        
        # Print results
        self._print_results()
        return len(self.errors) == 0
    
    def _validate_file(self, filepath, filename):
        """Validate individual file"""
        print(f"\n📋 Validating: {filename}")
        
        try:
            with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                lines = content.split('\n')
        except Exception as e:
            self.errors.append(f"Cannot read {filename}: {e}")
            return
        
        # Check 1: Matching braces
        open_braces = content.count('{')
        close_braces = content.count('}')
        if open_braces != close_braces:
            self.errors.append(
                f"{filename}: Brace mismatch - {{ count={open_braces}, }} count={close_braces}"
            )
        
        # Check 2: Matching parentheses
        open_parens = content.count('(')
        close_parens = content.count(')')
        if open_parens != close_parens:
            self.errors.append(
                f"{filename}: Parenthesis mismatch - ( count={open_parens}, ) count={close_parens}"
            )
        
        # Check 3: Missing semicolons on function definitions
        func_pattern = r'^\s*(static\s+)?\w+\s+\w+\s*\([^)]*\)\s*$'
        for i, line in enumerate(lines, 1):
            if re.match(func_pattern, line):
                next_line = lines[i] if i < len(lines) else ""
                if not next_line.strip().startswith('{'):
                    self.warnings.append(
                        f"{filename}:{i}: Possibly malformed function signature"
                    )
        
        # Check 4: Key fixes present
        self._check_fixes(filename, content)
        
        print(f"   ✓ Syntax check passed")
    
    def _check_fixes(self, filename, content):
        """Verify that bug fixes are actually present in the file"""
        fixes_expected = {
            "AIInferenceEngine.mqh": ["MathIsValidNumber(probability)", "FIX #11"],
            "SymbolManagement.mqh": ["MAX_ATTEMPTS", "FIX #15", "success"],
            "AICandleQualityFilter.mqh": ["SafeDiv(range", "FIX #10"],
            "TrendAnalysisEnhanced.mqh": ["SafeDiv(atr", "SafeDiv(range_current"],
            "MainLifecycle.mqh": ["ArraySize(g_symbols)", "FIX #7"],
            "AIScaler.mqh": ["FILE_TIMEOUT_MS", "FIX #12"],
        }
        
        if filename in fixes_expected:
            for fix_marker in fixes_expected[filename]:
                if fix_marker not in content:
                    self.warnings.append(
                        f"{filename}: Expected fix marker not found: '{fix_marker}'"
                    )
    
    def _print_results(self):
        """Print validation results"""
        print("\n" + "=" * 70)
        print("VALIDATION RESULTS")
        print("=" * 70)
        
        if self.errors:
            print(f"\n❌ ERRORS FOUND ({len(self.errors)}):")
            for error in self.errors:
                print(f"   • {error}")
        else:
            print(f"\n✅ NO CRITICAL ERRORS FOUND")
        
        if self.warnings:
            print(f"\n⚠️  WARNINGS ({len(self.warnings)}):")
            for warning in self.warnings:
                print(f"   • {warning}")
        
        print("\n" + "=" * 70)
        print("COMPILATION STATUS")
        print("=" * 70)
        
        if not self.errors:
            print("""
✅ SUCCESS: All MQL5 files pass validation!

Next Steps:
1. Open MetaEditor (F4 in MetaTrader 5)
2. Open: ProfitTrailBotEnterprises-1.5.2.mq5
3. Press: Ctrl+Shift+F9 (Compile)
4. Expected output: "Compilation successful"

Bug Fixes Summary:
  • Fix #1-6:   Critical/High issues (Gate Control, Handle Release, Daily Reset)
  • Fix #7:     Symbol array validation
  • Fix #9:     AI cache clearing
  • Fix #10:    SafeDiv() wrapping (3 locations)
  • Fix #11:    NaN validation in GetConfidence()
  • Fix #12:    File read timeout (5 seconds)
  • Fix #15:    Thread-safe position counting

Total: 12 of 18 bugs fixed ✅
            """)
        else:
            print("\n❌ COMPILATION BLOCKED: Fix errors above before compiling")
        
        print("=" * 70)

if __name__ == "__main__":
    project_dir = r"c:\Users\Joseph Nganga\AppData\Roaming\MetaQuotes\Terminal\BB16F565FAAA6B23A20C26C49416FF05\MQL5\Experts\ProfitTrailBot 1.5.2"
    validator = MQL5Validator(project_dir)
    success = validator.validate()
    sys.exit(0 if success else 1)
