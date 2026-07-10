# ProfitTrailBot Bug Fix Backtest Runner
# Runs the fixed code against XAUUSD with optimized parameters
# Date: April 6, 2026

param(
    [string]$TerminalPath = "C:\Program Files\MetaTrader 5\terminal64.exe",
    [string]$ProfilePath = "BB16F565FAAA6B23A20C26C49416FF05",
    [string]$ConfigFile = "backtest_bugfixes_20260406.ini",
    [bool]$WaitForCompletion = $true,
    [int]$TimeoutMinutes = 180
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ProfitTrailBot v1.5.2 - Bug Fix Backtest" -ForegroundColor Cyan
Write-Host "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Validate inputs
if (-not (Test-Path $TerminalPath)) {
    Write-Host "ERROR: Terminal not found at $TerminalPath" -ForegroundColor Red
    exit 1
}

$ProfileDir = Join-Path "C:\Users\Joseph Nganga\AppData\Roaming\MetaQuotes\Terminal" $ProfilePath
if (-not (Test-Path $ProfileDir)) {
    Write-Host "ERROR: Profile not found at $ProfileDir" -ForegroundColor Red
    exit 1
}

$ConfigPath = Join-Path $ProfileDir "MQL5\Experts\ProfitTrailBot 1.5.2\smoke_test_matrix_v3" $ConfigFile
if (-not (Test-Path $ConfigPath)) {
    Write-Host "ERROR: Config file not found at $ConfigPath" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Terminal path: $TerminalPath" -ForegroundColor Green
Write-Host "✓ Profile: $ProfilePath" -ForegroundColor Green
Write-Host "✓ Config: $ConfigFile" -ForegroundColor Green
Write-Host ""

Write-Host "Starting backtest..." -ForegroundColor Yellow
Write-Host "- Symbol: XAUUSD" -ForegroundColor Yellow
Write-Host "- Period: M15" -ForegroundColor Yellow
Write-Host "- Range: 2025-10-01 to 2026-04-06" -ForegroundColor Yellow
Write-Host "- Deposit: $1000 USD" -ForegroundColor Yellow
Write-Host "- Risk: Conservative (0.5% risk, 2.0 min R/R)" -ForegroundColor Yellow
Write-Host "- Bug Fixes: C1, C2, C3, C5, H2, M1, M2, H1, H3, C4" -ForegroundColor Yellow
Write-Host ""

# Start backtest
try {
    # MT5 command line: terminal.exe /portable /profile:profile /config:path/to/config.ini
    $Args = @(
        "/portable",
        "/profile:$ProfilePath",
        "/config:$ConfigPath"
    )
    
    Write-Host "Running: $TerminalPath with args:" -ForegroundColor Cyan
    Write-Host "  $($Args -join ' ')" -ForegroundColor Cyan
    Write-Host ""
    
    $StartTime = Get-Date
    $Process = Start-Process -FilePath $TerminalPath -ArgumentList $Args -NoNewWindow -PassThru
    
    if ($WaitForCompletion) {
        Write-Host "Waiting for backtest to complete (timeout: $TimeoutMinutes minutes)..." -ForegroundColor Yellow
        $TimeoutSeconds = $TimeoutMinutes * 60
        $Elapsed = 0
        
        while (-not $Process.HasExited -and $Elapsed -lt $TimeoutSeconds) {
            Start-Sleep -Seconds 10
            $Elapsed += 10
            $Minutes = [math]::Round($Elapsed / 60, 1)
            Write-Host "  [$Minutes/$TimeoutMinutes min] Running..." -ForegroundColor Gray
        }
        
        if ($Process.HasExited) {
            $Duration = (Get-Date) - $StartTime
            Write-Host ""
            Write-Host "✓ Backtest completed in $($Duration.TotalMinutes.ToString('F1')) minutes" -ForegroundColor Green
            
            # Try to find results
            $ReportDir = Join-Path $ProfileDir "MQL5\Tester\Files"
            if (Test-Path $ReportDir) {
                $Reports = Get-ChildItem $ReportDir -Filter "*bugfixes*" -Recurse | Sort-Object LastWriteTime -Descending | Select-Object -First 3
                if ($Reports) {
                    Write-Host ""
                    Write-Host "Latest reports found:" -ForegroundColor Green
                    foreach ($Report in $Reports) {
                        Write-Host "  - $($Report.FullName)" -ForegroundColor Cyan
                    }
                }
            }
        } else {
            Write-Host ""
            Write-Host "⚠ Timeout reached ($TimeoutMinutes minutes). Backtest may still be running." -ForegroundColor Yellow
        }
    } else {
        Write-Host "✓ Backtest started in background (PID: $($Process.Id))" -ForegroundColor Green
        Write-Host "  Monitor MT5 terminal for progress" -ForegroundColor Gray
    }
    
} catch {
    Write-Host "ERROR: Failed to start backtest" -ForegroundColor Red
    Write-Host "$_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Backtest run completed" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
