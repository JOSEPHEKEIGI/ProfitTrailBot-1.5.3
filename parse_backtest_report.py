#!/usr/bin/env python3
"""
Parse MT5 HTML Backtest Reports
Extracts key metrics and validates strategy performance
"""

import re
import sys
import json
from pathlib import Path
from typing import Dict, Optional, Tuple


class BacktestReportParser:
    """Parse MetaTrader 5 HTML backtest reports"""
    
    def __init__(self, report_path: str):
        self.path = Path(report_path)
        self.content = None
        self.metrics = {}
        
        if not self.path.exists():
            raise FileNotFoundError(f"Report not found: {report_path}")
        
        # Read with fallback encodings for MT5 reports
        for encoding in ['utf-8', 'utf-16', 'cp1252', 'latin-1']:
            try:
                with open(self.path, 'r', encoding=encoding) as f:
                    self.content = f.read()
                break
            except UnicodeDecodeError:
                continue
        
        if not self.content:
            raise ValueError(f"Could not decode report: {report_path}")
    
    def extract(self, pattern: str, default=None):
        """Extract value using regex"""
        match = re.search(pattern, self.content, re.IGNORECASE | re.DOTALL)
        if match:
            value = match.group(1).strip() if match.lastindex >= 1 else match.group(0)
            return value
        return default
    
    def clean_number(self, text: str) -> float:
        """Convert text to number"""
        if not text:
            return 0.0
        cleaned = re.sub(r'[^\d.-]', '', str(text).strip())
        try:
            return float(cleaned)
        except ValueError:
            return 0.0
    
    def parse(self) -> Dict:
        """Parse all metrics from report"""
        self.metrics = {
            'overview': self._parse_overview(),
            'summary': self._parse_summary(),
            'results': self._parse_results(),
            'performance': self._parse_performance(),
            'trades': self._parse_trade_list()
        }
        return self.metrics
    
    def _parse_overview(self) -> Dict:
        """Test overview information"""
        return {
            'test_start': self.extract(r'Start date\s*<[^>]+>\s*([^<]+)', 'N/A'),
            'test_end': self.extract(r'End date\s*<[^>]+>\s*([^<]+)', 'N/A'),
            'symbol': self.extract(r'Symbol\s*<[^>]+>\s*([^<]+)', 'N/A'),
            'period': self.extract(r'Period\s*<[^>]+>\s*([^<]+)', 'N/A'),
            'model': self.extract(r'Model\s*<[^>]+>\s*([^<]+)', 'EVT'),
            'initial_deposit': self.clean_number(
                self.extract(r'Initial deposit\s*<[^>]+>\s*([^<]+)', '10000')
            ),
        }
    
    def _parse_summary(self) -> Dict:
        """Trade summary statistics"""
        summary = {}
        
        # Total trades
        total_match = self.extract(r'Total trades\s*<[^>]+>\s*(\d+)')
        if total_match:
            summary['total_trades'] = int(total_match)
        
        # Profitable trades
        profit_match = self.extract(r'(?:Profitable|Winning) trades\s*<[^>]+>\s*(\d+)')
        if profit_match:
            summary['profitable_trades'] = int(profit_match)
            total = summary.get('total_trades', 1)
            summary['win_rate'] = int(profit_match) / max(total, 1) * 100
        
        # Long positions
        long_match = self.extract(r'Long positions\s*<[^>]+>\s*(\d+)')
        if long_match:
            summary['long_trades'] = int(long_match)
        
        # Short positions
        short_match = self.extract(r'Short positions\s*<[^>]+>\s*(\d+)')
        if short_match:
            summary['short_trades'] = int(short_match)
        
        return summary
    
    def _parse_results(self) -> Dict:
        """Trade results (P&L)"""
        results = {}
        
        # Gross profit/loss
        gross_profit_match = self.extract(r'Gross profit\s*<[^>]+>\s*([^\<]+)')
        if gross_profit_match:
            results['gross_profit'] = self.clean_number(gross_profit_match)
        
        gross_loss_match = self.extract(r'Gross loss\s*<[^>]+>\s*([^\<]+)')
        if gross_loss_match:
            results['gross_loss'] = self.clean_number(gross_loss_match)
        
        # Profit factor
        pf_match = self.extract(r'Profit factor\s*<[^>]+>\s*([^\<]+)')
        if pf_match:
            results['profit_factor'] = self.clean_number(pf_match)
        
        # Best/Worst/Avg trade
        best_match = self.extract(r'Best trade\s*<[^>]+>\s*([^\<]+)')
        if best_match:
            results['best_trade'] = self.clean_number(best_match)
        
        worst_match = self.extract(r'Worst trade\s*<[^>]+>\s*([^\<]+)')
        if worst_match:
            results['worst_trade'] = self.clean_number(worst_match)
        
        avg_match = self.extract(r'Average trade\s*<[^>]+>\s*([^\<]+)')
        if avg_match:
            results['average_trade'] = self.clean_number(avg_match)
        
        # Max consecutive wins/losses
        max_wins = self.extract(r'Maximum consecutive wins\s*<[^>]+>\s*(\d+)')
        if max_wins:
            results['max_consecutive_wins'] = int(max_wins)
        
        max_losses = self.extract(r'Maximum consecutive losses\s*<[^>]+>\s*(\d+)')
        if max_losses:
            results['max_consecutive_losses'] = int(max_losses)
        
        return results
    
    def _parse_performance(self) -> Dict:
        """Risk and performance metrics"""
        perf = {}
        
        # Drawdown
        abs_dd = self.extract(r'Absolute drawdown\s*<[^>]+>\s*([^\<]+)')
        if abs_dd:
            perf['absolute_drawdown'] = self.clean_number(abs_dd)
        
        max_dd = self.extract(r'(?:Maximal|Maximum) drawdown\s*<[^>]+>\s*([^\<]+)')
        if max_dd:
            perf['max_drawdown'] = self.clean_number(max_dd)
        
        # Relative drawdown
        rel_dd = self.extract(r'Relative drawdown\s*<[^>]+>\s*([^\<]+)')
        if rel_dd:
            perf['relative_drawdown'] = self.clean_number(rel_dd)
        
        # Sharpe ratio
        sharpe = self.extract(r'Sharpe ratio\s*<[^>]+>\s*([-\d.]+)')
        if sharpe:
            perf['sharpe_ratio'] = self.clean_number(sharpe)
        
        # Recovery factor
        recovery = self.extract(r'Recovery factor\s*<[^>]+>\s*([-\d.]+)')
        if recovery:
            perf['recovery_factor'] = self.clean_number(recovery)
        
        # Payoff ratio
        payoff = self.extract(r'Payoff ratio\s*<[^>]+>\s*([-\d.]+)')
        if payoff:
            perf['payoff_ratio'] = self.clean_number(payoff)
        
        return perf
    
    def _parse_trade_list(self) -> list:
        """Parse individual trades if available"""
        trades = []
        
        # Find trade table rows
        trade_pattern = r'<tr[^>]*>.*?<td[^>]*>(\d+)</td>.*?<td[^>]*>(\w+)'
        for match in re.finditer(trade_pattern, self.content, re.DOTALL):
            trades.append({
                'ticket': match.group(1),
                'type': match.group(2)
            })
        
        return trades
    
    def validate(self) -> Tuple[bool, str]:
        """Validate backtest results"""
        errors = []
        summary = self.metrics.get('summary', {})
        results = self.metrics.get('results', {})
        perf = self.metrics.get('performance', {})
        
        # Check for trades executed
        total_trades = summary.get('total_trades', 0)
        if total_trades == 0:
            errors.append("No trades executed - check market conditions")
            return False, "; ".join(errors)
        
        if total_trades < 5:
            errors.append(f"Too few trades ({total_trades}, need 5+)")
        
        # Win rate validation
        win_rate = summary.get('win_rate', 0)
        if win_rate < 20:
            errors.append(f"Win rate too low ({win_rate:.1f}%)")
        elif win_rate > 80:
            errors.append(f"Win rate suspiciously high ({win_rate:.1f}%)")
        
        # Profit factor validation
        pf = results.get('profit_factor', 1.0)
        if pf < 1.0:
            errors.append(f"Negative profit factor ({pf:.2f})")
        elif pf < 1.5:
            errors.append(f"Profit factor marginal ({pf:.2f}, target 1.5+)")
        
        # Drawdown validation
        max_dd = perf.get('max_drawdown', 0)
        if max_dd > 15:
            errors.append(f"Max drawdown high ({max_dd:.1f}%)")
        
        passed = len(errors) == 0
        message = "; ".join(errors) if errors else "ALL CHECKS PASSED"
        
        return passed, message
    
    def print_summary(self, verbose=False):
        """Print formatted summary"""
        print("\n" + "="*70)
        print("BACKTEST REPORT ANALYSIS")
        print("="*70)
        
        # Overview
        overview = self.metrics.get('overview', {})
        print(f"\nTest Period: {overview.get('test_start')} to {overview.get('test_end')}")
        print(f"Symbol: {overview.get('symbol')} | Period: {overview.get('period')}")
        
        # Summary
        summary = self.metrics.get('summary', {})
        print(f"\n--- TRADES ---")
        print(f"Total Trades:       {summary.get('total_trades', 0)}")
        print(f"Profitable:         {summary.get('profitable_trades', 0)}")
        print(f"Win Rate:           {summary.get('win_rate', 0):.2f}%")
        if summary.get('long_trades'):
            print(f"Long/Short:         {summary.get('long_trades', 0)} / {summary.get('short_trades', 0)}")
        
        # Results
        results = self.metrics.get('results', {})
        print(f"\n--- FINANCIAL ---")
        print(f"Gross Profit:       {results.get('gross_profit', 0):>12.2f}")
        print(f"Gross Loss:         {results.get('gross_loss', 0):>12.2f}")
        print(f"Profit Factor:      {results.get('profit_factor', 0):>12.2f}", end="")
        pf = results.get('profit_factor', 0)
        if pf >= 1.5:
            print(" ✓ GOOD")
        elif pf >= 1.0:
            print(" ⚠ MARGINAL")
        else:
            print(" ✗ POOR")
        
        print(f"Best Trade:         {results.get('best_trade', 0):>12.2f}")
        print(f"Worst Trade:        {results.get('worst_trade', 0):>12.2f}")
        print(f"Average Trade:      {results.get('average_trade', 0):>12.2f}")
        
        # Performance
        perf = self.metrics.get('performance', {})
        print(f"\n--- RISK METRICS ---")
        max_dd = perf.get('max_drawdown', 0)
        print(f"Max Drawdown:       {max_dd:>12.2f}%", end="")
        if max_dd < 5:
            print(" ✓ EXCELLENT")
        elif max_dd < 10:
            print(" ✓ GOOD")
        else:
            print(" ⚠ HIGH")
        
        print(f"Sharpe Ratio:       {perf.get('sharpe_ratio', 0):>12.2f}")
        print(f"Recovery Factor:    {perf.get('recovery_factor', 0):>12.2f}")
        
        # Validation result
        is_valid, message = self.validate()
        print(f"\n--- VALIDATION ---")
        status = "✓ PASSED" if is_valid else "✗ FAILED"
        print(f"{status}: {message}")
        
        print("\n" + "="*70 + "\n")
        
        return is_valid


def main():
    """Main entry point"""
    if len(sys.argv) < 2:
        print("Usage: python parse_backtest_report.py <report_file.htm>")
        sys.exit(1)
    
    try:
        parser = BacktestReportParser(sys.argv[1])
        parser.parse()
        is_valid = parser.print_summary()
        
        # Save as JSON
        json_path = Path(sys.argv[1]).with_suffix('.json')
        with open(json_path, 'w') as f:
            json.dump(parser.metrics, f, indent=2)
        print(f"Metrics saved to: {json_path}")
        
        sys.exit(0 if is_valid else 1)
        
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
