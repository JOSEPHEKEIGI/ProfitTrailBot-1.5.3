#!/usr/bin/env pwsh
<#
.SYNOPSIS
Master Monitoring Dashboard for ProfitTrailBot
Consolidates compilation, backtest, and demo trading monitoring

.DESCRIPTION
Real-time monitoring of EA status, trading metrics, and system health.
Integrates compile verification, backtest results, and live demo monitoring.

.PARAMETER Action
- status    : Show current EA status
- logs      : Monitor live logs with filtering
- backtest  : Show latest backtest metrics
- demo      : Show demo trading summary
- health    : System health check
- all       : Full monitoring dashboard

.PARAMETER Filter
Log filter (default: "TRADE|GATE|ERROR")

.EXAMPLE
.\monitor_dashboard.ps1 -Action all
.\monitor_dashboard.ps1 -Action logs -Filter "ERROR|CRITICAL"
.\monitor_dashboard.ps1 -Action status
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('status', 'logs', 'backtest', 'demo', 'health', 'all')]
    [string]$Action = 'all',
    
    [Parameter(Mandatory=$false)]
    [string]$Filter = "TRADE|GATE|ERROR",
    
    [Parameter(Mandatory=$false)]
    [int]$TailLines = 50
)

$ErrorActionPreference = 'SilentlyContinue'
$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Write-Status {
    param([string]$Message, [ValidateSet('info', 'success', 'warning', 'error')]$Level = 'info')
    
    $colors = @{
        'info'    = [System.ConsoleColor]::Cyan
        'success' = [System.ConsoleColor]::Green
        'warning' = [System.ConsoleColor]::Yellow
        'error'   = [System.ConsoleColor]::Red
    }
    
    $symbol = @{
        'info'    = '[•]'
        'success' = '[✓]'
        'warning' = '[!]'
        'error'   = '[✗]'
    }
    
    Write-Host "$($symbol[$Level]) " -ForegroundColor $colors[$Level] -NoNewline
    Write-Host $Message
}

function Get-EA-Status {
    Write-Host "`n" + "=" * 60
    Write-Host "EA COMPILATION & RUNTIME STATUS" -ForegroundColor Cyan
    Write-Host "=" * 60
    
    # Check .ex5 file
    $exFile = Join-Path $projectDir "ProfitTrailBotEnterprises-1.5.2.ex5"
    if (Test-Path $exFile) {
        $fileInfo = Get-Item $exFile
        $fileSize = $fileInfo.Length / 1KB
        Write-Status "EA Binary (.ex5)" success
        Write-Host "  Size: $([math]::Round($fileSize, 1)) KB"
        Write-Host "  Modified: $($fileInfo.LastWriteTime)"
    } else {
        Write-Status "EA Binary (.ex5)" error
        Write-Host "  File not found - needs compilation"
    }
    
    # Check include files
    Write-Status "Include Files" info
    $mqhFiles = @(
        "MainLifecycle.mqh",
        "SignalGeneration.mqh",
        "TradeManagement.mqh",
        "RiskSession.mqh",
        "ConfidenceFusionRouter.mqh"
    )
    
    $missingFiles = @()
    foreach ($file in $mqhFiles) {
        if (Test-Path (Join-Path $projectDir $file)) {
            Write-Host "  ✓ $file"
        } else {
            Write-Host "  ✗ $file (MISSING!)"
            $missingFiles += $file
        }
    }
    
    if ($missingFiles.Count -eq 0) {
        Write-Status "All critical includes present" success
    } else {
        Write-Status "Missing $($missingFiles.Count) files - compilation may fail" error
    }
    
    # Compilation log
    Write-Status "Latest Compilation Log" info
    $latestLog = Get-ChildItem (Join-Path $projectDir "compile_log_*.txt") -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Desc |
        Select-Object -First 1
    
    if ($latestLog) {
        Write-Host "  File: $($latestLog.Name)"
        Write-Host "  Date: $($latestLog.LastWriteTime)"
        
        $logContent = Get-Content $latestLog.FullName
        if ($logContent -match "SUCCESS|successful") {
            Write-Status "Compilation Status: SUCCESS" success
        } elseif ($logContent -match "error|failed") {
            Write-Status "Compilation Status: FAILED" error
            Write-Host "`n  Last 5 lines:"
            $logContent | Select-Object -Last 5 | ForEach-Object { Write-Host "  $_" }
        } else {
            Write-Status "Compilation Status: UNKNOWN" warning
        }
    } else {
        Write-Status "No compilation log found - run compilation first" warning
    }
}

function Get-EA-Logs {
    Write-Host "`n" + "=" * 60
    Write-Host "EA RUNTIME LOGS (Latest $TailLines lines)" -ForegroundColor Cyan
    Write-Host "=" * 60
    
    $logPattern = Join-Path $projectDir "MQL5\Logs\*.log"
    $logFiles = @(
        "C:\Users\Joseph Nganga\AppData\Roaming\MetaQuotes\Terminal\BB16F565FAAA6B23A20C26C49416FF05\MQL5\Logs\20260304.log"
    )
    
    $foundLogs = $false
    foreach ($logFile in $logFiles) {
        if (Test-Path $logFile) {
            $foundLogs = $true
            Write-Status "Log: $logFile" info
            
            $content = Get-Content $logFile -Tail $TailLines
            $content | Select-String $Filter | ForEach-Object {
                if ($_ -match "ERROR|FAIL") {
                    Write-Host "  " -NoNewline
                    Write-Host $_.Line -ForegroundColor Red
                } elseif ($_ -match "TRADE|SUCCESS") {
                    Write-Host "  " -NoNewline
                    Write-Host $_.Line -ForegroundColor Green
                } elseif ($_ -match "GATE|WARNING") {
                    Write-Host "  " -NoNewline
                    Write-Host $_.Line -ForegroundColor Yellow
                } else {
                    Write-Host "  $($_.Line)" -ForegroundColor Cyan
                }
            }
        }
    }
    
    if (-not $foundLogs) {
        Write-Status "No EA logs found - EA may not be running" warning
        Write-Host "  Check: Window → Experts in MetaTrader 5"
    }
}

function Get-Backtest-Results {
    Write-Host "`n" + "=" * 60
    Write-Host "BACKTEST RESULTS SUMMARY" -ForegroundColor Cyan
    Write-Host "=" * 60
    
    # Find latest HTML report
    $reports = Get-ChildItem (Join-Path $projectDir "backtest_report_*.htm") -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Desc
    
    if ($reports.Count -eq 0) {
        Write-Status "No backtest reports found" warning
        Write-Host "  Run a backtest in MT5 Strategy Tester first"
        return
    }
    
    # Summary of latest report
    $latest = $reports[0]
    Write-Status "Latest Report: $($latest.Name)" info
    Write-Host "  Date: $($latest.LastWriteTime)"
    Write-Host "  Size: $([math]::Round($latest.Length / 1KB, 1)) KB"
    
    # Check for JSON analysis
    $jsonReport = $latest.FullName.Replace('.htm', '.json')
    if (Test-Path $jsonReport) {
        Write-Status "Parsing analysis..." info
        
        try {
            $analysis = Get-Content $jsonReport | ConvertFrom-Json
            
            # Summary metrics
            $summary = $analysis.summary
            $results = $analysis.results
            $perf = $analysis.performance
            
            Write-Host "`n  Trades: $($summary.total_trades) (WR: $([math]::Round($summary.win_rate, 1))%)"
            Write-Host "  Profit Factor: $([math]::Round($results.profit_factor, 2))"
            Write-Host "  Max Drawdown: $([math]::Round($perf.max_drawdown, 2))%"
            Write-Host "  Sharpe Ratio: $([math]::Round($perf.sharpe_ratio, 2))"
            
            # Validation status
            if ($results.profit_factor -ge 1.5 -and $summary.total_trades -ge 50) {
                Write-Status "Backtest Results: PASSED" success
            } else {
                Write-Status "Backtest Results: MARGINAL - Review parameters" warning
            }
        } catch {
            Write-Status "Could not parse JSON analysis" error
        }
    } else {
        Write-Status "Run: python parse_backtest_report.py $($latest.FullName)" info
    }
    
    # List recent reports
    Write-Host "`n  Recent reports (last 3):"
    $reports | Select-Object -First 3 | ForEach-Object {
        Write-Host "    $('{0:yyyy-MM-dd HH:mm}' -f $_.LastWriteTime)  $($_.Name)"
    }
}

function Get-Demo-Trading-Summary {
    Write-Host "`n" + "=" * 60
    Write-Host "DEMO TRADING MONITORING" -ForegroundColor Cyan
    Write-Host "=" * 60
    
    Write-Status "Demo Account Status" info
    Write-Host "  Status: Connect to MetaTrader 5 to see live data"
    Write-Host "  Chart: XAUUSD M15 (verify EA attached)"
    Write-Host "  Check: Window → Experts (should show green indicator)"
    
    Write-Host "`n  Key Metrics to Monitor:"
    Write-Host "    • Trade entry cleanness (fills within 2-3 pips of signal)"
    Write-Host "    • Daily trade count (should match backtest average)"
    Write-Host "    • Win rate consistency (should match 55-60% range)"
    Write-Host "    • Drawdown management (should pause at circuit breaker)"
    Write-Host "    • Order lifecycle (open → take profit or stop loss)"
    
    Write-Host "`n  Daily Checklist:"
    Write-Host "    □ EA running (green triangle in Experts)"
    Write-Host "    □ At least 2-4 trades per day"
    Write-Host "    □ No error messages in logs"
    Write-Host "    □ P&L within expected range (±10% of backtest)"
    Write-Host "    □ Daily reset working (counters clear at market open)"
    
    Write-Status "Documentation" info
    Write-Host "  See: COMPILATION_AND_TESTING_GUIDE.md"
    Write-Host "       DEPLOYMENT_CHECKLIST.md"
    Write-Host "       PIPELINE_DEBUG_ANALYSIS.md"
}

function Get-System-Health {
    Write-Host "`n" + "=" * 60
    Write-Host "SYSTEM HEALTH CHECK" -ForegroundColor Cyan
    Write-Host "=" * 60
    
    $checks = @()
    
    # Disk space
    $drive = Get-PSDrive C
    $freeGB = [math]::Round($drive.Free / 1GB, 1)
    if ($freeGB -gt 10) {
        Write-Status "Disk Space: $freeGB GB free" success
    } else {
        Write-Status "Disk Space: $freeGB GB (LOW!)" error
    }
    
    # .ex5 file
    if (Test-Path (Join-Path $projectDir "ProfitTrailBotEnterprises-1.5.2.ex5")) {
        Write-Status ".ex5 File: Present" success
    } else {
        Write-Status ".ex5 File: MISSING" error
    }
    
    # Include files
    $includeCount = (Get-ChildItem (Join-Path $projectDir "*.mqh")).Count
    if ($includeCount -ge 20) {
        Write-Status "Include Files: $includeCount found" success
    } else {
        Write-Status "Include Files: $includeCount (LOW!)" warning
    }
    
    # MetaTrader installation
    if (Test-Path "C:\Program Files\MetaTrader 5\terminal64.exe") {
        Write-Status "MetaTrader 5: Installed" success
    } else {
        Write-Status "MetaTrader 5: Not found at standard path" warning
    }
    
    # Python availability
    $pythonTest = & { python --version 2>&1 }
    if ($pythonTest -match "Python") {
        Write-Status "Python: Available ($pythonTest)" success
    } else {
        Write-Status "Python: Not in PATH" warning
    }
    
    # PowerShell version
    if ($PSVersionTable.PSVersion.Major -ge 5) {
        Write-Status "PowerShell: v$($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)" success
    } else {
        Write-Status "PowerShell: Outdated - upgrade recommended" warning
    }
}

function Show-Dashboard {
    Write-Host "`n"
    Write-Host "╔" + "═" * 58 + "╗" -ForegroundColor Cyan
    Write-Host "║ PROFITTRAILBOT MASTER MONITORING DASHBOARD              ║" -ForegroundColor Cyan
    Write-Host "║ Version 1.5.2 - $(Get-Date -f 'yyyy-MM-dd HH:mm')                      ║" -ForegroundColor Cyan
    Write-Host "╚" + "═" * 58 + "╝" -ForegroundColor Cyan
    
    Get-EA-Status
    Get-EA-Logs
    Get-Backtest-Results
    Get-Demo-Trading-Summary
    Get-System-Health
    
    Write-Host "`n" + "═" * 60
    Write-Host "QUICK COMMANDS" -ForegroundColor Cyan
    Write-Host "═" * 60
    Write-Host "  .\monitor_dashboard.ps1 -Action status        (EA status only)"
    Write-Host "  .\monitor_dashboard.ps1 -Action logs           (Recent logs)"
    Write-Host "  .\monitor_dashboard.ps1 -Action backtest       (Backtest summary)"
    Write-Host "  .\monitor_dashboard.ps1 -Action health         (System health)"
    Write-Host "  .\compile_and_test.ps1 -Action compile         (Compile EA)"
    Write-Host "  python parse_backtest_report.py <report.htm>   (Analyze backtest)"
    Write-Host "`n"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

switch ($Action) {
    'status'   { Get-EA-Status }
    'logs'     { Get-EA-Logs }
    'backtest' { Get-Backtest-Results }
    'demo'     { Get-Demo-Trading-Summary }
    'health'   { Get-System-Health }
    'all'      { Show-Dashboard }
    default    { Show-Dashboard }
}

Write-Host ""
