#requires -Version 5.0
<#
.SYNOPSIS
    ProfitTrailBot Compilation & Testing Automation Script
    
.DESCRIPTION
    Automates compilation, initial backtest, and result analysis
    
.EXAMPLE
    .\compile_and_test.ps1 -Action compile
    .\compile_and_test.ps1 -Action backtest
    .\compile_and_test.ps1 -Action analyze
#>

param(
    [ValidateSet('compile', 'backtest', 'analyze', 'all')]
    [string]$Action = 'all',
    
    [string]$MetaEditorPath = 'C:\Program Files\MetaTrader 5\metaeditor64.exe',
    [string]$ProjectPath = 'C:\Users\Joseph Nganga\AppData\Roaming\MetaQuotes\Terminal\BB16F565FAAA6B23A20C26C49416FF05\MQL5\Experts\ProfitTrailBot 1.5.2',
    [string]$EAName = 'ProfitTrailBotEnterprises-1.5.2'
)

# ===========================
# CONFIGURATION
# ===========================

$LogFile = Join-Path $ProjectPath "compilation_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$ConfigFile = Join-Path $ProjectPath "backtest_config.ini"
$ResultsFolder = Join-Path $ProjectPath "backtest_results"

# ===========================
# LOGGING FUNCTIONS
# ===========================

function Write-Log {
    param([string]$Message, [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]$Level = 'INFO')
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $output = "[$timestamp] [$Level] $Message"
    
    Write-Host $output
    Add-Content -Path $LogFile -Value $output
}

function Write-Section {
    param([string]$Title)
    Write-Log "========================================" INFO
    Write-Log $Title INFO
    Write-Log "========================================" INFO
}

# ===========================
# COMPILATION PHASE
# ===========================

function Invoke-Compilation {
    Write-Section "PHASE 1: COMPILATION"
    
    # Verify MetaEditor exists
    if (-not (Test-Path $MetaEditorPath)) {
        Write-Log "ERROR: MetaEditor not found at $MetaEditorPath" ERROR
        return $false
    }
    Write-Log "MetaEditor found: $MetaEditorPath" SUCCESS
    
    # Verify project path exists
    if (-not (Test-Path $ProjectPath)) {
        Write-Log "ERROR: Project path not found: $ProjectPath" ERROR
        return $false
    }
    Write-Log "Project path verified: $ProjectPath" SUCCESS
    
    # Check main MQ5 file
    $mq5File = Join-Path $ProjectPath "$EAName.mq5"
    if (-not (Test-Path $mq5File)) {
        Write-Log "ERROR: MQ5 file not found: $mq5File" ERROR
        return $false
    }
    Write-Log "MQ5 file found: $mq5File" SUCCESS
    
    # Check all include files
    Write-Log "Verifying include files..." INFO
    $includes = @(
        'MainLifecycle.mqh',
        'SignalGeneration.mqh',
        'TradeManagement.mqh',
        'RiskSession.mqh',
        'ICTStrategy.mqh',
        'AIInferenceEngine.mqh',
        'KImanizStrategy.mqh',
        'ConfidenceFusionRouter.mqh'
    )
    
    $missingIncludes = @()
    foreach ($include in $includes) {
        $includePath = Join-Path $ProjectPath $include
        if (-not (Test-Path $includePath)) {
            $missingIncludes += $include
            Write-Log "WARNING: Missing include file: $include" WARNING
        }
    }
    
    if ($missingIncludes.Count -gt 0) {
        Write-Log "ERROR: $($missingIncludes.Count) include files missing" ERROR
        return $false
    }
    Write-Log "All include files verified" SUCCESS
    
    # Attempt compilation via MetaEditor command line
    Write-Log "Compiling $EAName..." INFO
    
    try {
        $compileCmd = "`"$MetaEditorPath`" /compile:`"$mq5File`" /log:`"$LogFile`""
        Write-Log "Executing: $compileCmd" INFO
        
        $process = Start-Process -FilePath $MetaEditorPath -ArgumentList "/compile:`"$mq5File`" /log:`"$LogFile`"" -PassThru -NoNewWindow
        $process.WaitForExit(300000)  # 5 minute timeout
        
        if ($process.ExitCode -eq 0) {
            Write-Log "Compilation SUCCESSFUL" SUCCESS
            
            # Verify .ex5 file was created
            $ex5File = $mq5File -replace '\.mq5$', '.ex5'
            if (Test-Path $ex5File) {
                $fileSize = (Get-Item $ex5File).Length / 1KB
                Write-Log "Generated .ex5 file: $ex5File ($fileSize KB)" SUCCESS
                return $true
            }
            else {
                Write-Log "WARNING: .ex5 file not found after successful compilation" WARNING
                return $true
            }
        }
        else {
            Write-Log "Compilation FAILED with exit code: $($process.ExitCode)" ERROR
            
            # Parse compilation log for errors
            if (Test-Path $LogFile) {
                Write-Log "Recent compilation errors:" ERROR
                Get-Content $LogFile | Select-Object -Last 20 | ForEach-Object {
                    if ($_ -match 'error|Error|ERROR') {
                        Write-Log $_ ERROR
                    }
                }
            }
            return $false
        }
    }
    catch {
        Write-Log "Compilation exception: $_" ERROR
        return $false
    }
}

# ===========================
# BACKTEST CONFIGURATION
# ===========================

function Create-BacktestConfig {
    param(
        [ValidateSet('smoke', 'extended', 'multi')]$Type = 'smoke'
    )
    
    Write-Section "BACKTEST CONFIGURATION: $Type"
    
    $configs = @{
        'smoke' = @{
            'Symbol' = 'XAUUSD'
            'Period' = 'M15'
            'SymbolPrefix' = ''
            'DateFrom' = [datetime]::Today.AddDays(-7).ToString('yyyy.MM.dd')
            'DateTo' = [datetime]::Today.ToString('yyyy.MM.dd')
            'Optimization' = 'Off'
            'ModelType' = 'EveryTick'
            'LegacyMode' = 'Off'
            'Risk' = '0.25'
            'MaxTrades' = '4'
            'MaxConcurrent' = '1'
            'Description' = 'Quick smoke test (5-10 days)'
        }
        'extended' = @{
            'Symbol' = 'XAUUSD'
            'Period' = 'M15'
            'SymbolPrefix' = ''
            'DateFrom' = [datetime]::Today.AddDays(-60).ToString('yyyy.MM.dd')
            'DateTo' = [datetime]::Today.ToString('yyyy.MM.dd')
            'Optimization' = 'Off'
            'ModelType' = 'EveryTick'
            'LegacyMode' = 'Off'
            'Risk' = '0.25'
            'MaxTrades' = '4'
            'MaxConcurrent' = '1'
            'Description' = 'Extended validation (60 days, 50+ trades)'
        }
        'multi' = @{
            'Symbol' = 'XAUUSD,EURUSD,GBPUSD'
            'Period' = 'M15'
            'SymbolPrefix' = ''
            'DateFrom' = [datetime]::Today.AddDays(-30).ToString('yyyy.MM.dd')
            'DateTo' = [datetime]::Today.ToString('yyyy.MM.dd')
            'Optimization' = 'Off'
            'ModelType' = 'EveryTick'
            'LegacyMode' = 'Off'
            'Risk' = '0.25'
            'MaxTrades' = '6'
            'MaxConcurrent' = '2'
            'Description' = 'Multi-symbol testing (30 days, 3 symbols)'
        }
    }
    
    $config = $configs[$Type]
    
    Write-Log "Backtest Type: $Type" INFO
    Write-Log "Description: $($config.Description)" INFO
    Write-Log "Symbol(s): $($config.Symbol)" INFO
    Write-Log "Period: $($config.Period)" INFO
    Write-Log "Date Range: $($config.DateFrom) to $($config.DateTo)" INFO
    Write-Log "Risk: $($config.Risk)%" INFO
    Write-Log "Max Trades/Day: $($config.MaxTrades)" INFO
    Write-Log "Max Concurrent: $($config.MaxConcurrent)" INFO
    
    return $config
}

# ===========================
# BACKTEST ANALYSIS
# ===========================

function Analyze-BacktestResults {
    Write-Section "BACKTEST RESULT ANALYSIS"
    
    # Look for recent backtest report
    $reportFile = Get-ChildItem -Path $ProjectPath -Filter "*.htm" -ErrorAction SilentlyContinue | 
                  Sort-Object LastWriteTime -Descending | 
                  Select-Object -First 1
    
    if (-not $reportFile) {
        Write-Log "No backtest report found. Run backtest in Strategy Tester first." WARNING
        return $false
    }
    
    Write-Log "Analyzing report: $($reportFile.Name)" INFO
    Write-Log "Last modified: $($reportFile.LastWriteTime)" INFO
    
    # Parse HTML report (basic parsing)
    $content = Get-Content $reportFile.FullName -Raw
    
    # Extract key metrics using regex
    $metrics = @{}
    
    # Total trades
    if ($content -match 'Total trades:\s*(\d+)') {
        $metrics['TotalTrades'] = [int]$matches[1]
    }
    
    # Profit
    if ($content -match 'Gross profit.*?(\d+\.?\d*)') {
        $metrics['GrossProfit'] = $matches[1]
    }
    
    # Win rate
    if ($content -match 'Profit\s*factor.*?(\d+\.?\d*)') {
        $metrics['ProfitFactor'] = $matches[1]
    }
    
    # Drawdown
    if ($content -match 'Absolute\s*drawdown.*?(\d+\.?\d*)') {
        $metrics['Drawdown'] = $matches[1]
    }
    
    # Display metrics
    Write-Log "--- KEY METRICS ---" INFO
    if ($metrics['TotalTrades']) {
        Write-Log "Total Trades: $($metrics['TotalTrades'])" INFO
        if ($metrics['TotalTrades'] -ge 50) {
            Write-Log "✓ Sufficient sample size (>= 50 trades)" SUCCESS
        }
        else {
            Write-Log "⚠ Low sample size (< 50 trades)" WARNING
        }
    }
    
    if ($metrics['GrossProfit']) {
        Write-Log "Gross Profit: $($metrics['GrossProfit'])" INFO
    }
    
    if ($metrics['ProfitFactor']) {
        Write-Log "Profit Factor: $($metrics['ProfitFactor'])" INFO
        if ([decimal]$metrics['ProfitFactor'] -ge 1.5) {
            Write-Log "✓ Good profit factor (>= 1.5)" SUCCESS
        }
        elseif ([decimal]$metrics['ProfitFactor'] -ge 1.0) {
            Write-Log "⚠ Marginal profit factor (1.0-1.5)" WARNING
        }
        else {
            Write-Log "✗ Poor profit factor (< 1.0)" ERROR
        }
    }
    
    if ($metrics['Drawdown']) {
        Write-Log "Max Drawdown: $($metrics['Drawdown'])" INFO
    }
    
    Write-Log "--- ANALYSIS COMPLETE ---" INFO
    return $true
}

# ===========================
# MAIN EXECUTION
# ===========================

function Main {
    Write-Log "========================================" INFO
    Write-Log "ProfitTrailBot Compilation & Test Start" INFO
    Write-Log "Action: $Action" INFO
    Write-Log "========================================" INFO
    
    $success = $true
    
    switch ($Action) {
        'compile' {
            $success = Invoke-Compilation
        }
        'backtest' {
            $config = Create-BacktestConfig -Type 'smoke'
            Write-Log "Manual Action Required: Open Strategy Tester in MT5 and start backtest with config shown above" WARNING
        }
        'analyze' {
            Analyze-BacktestResults
        }
        'all' {
            $success = Invoke-Compilation
            if ($success) {
                Write-Log "" INFO
                $config = Create-BacktestConfig -Type 'smoke'
                Write-Log "NEXT STEP: Run initial 5-10 day backtest in Strategy Tester" INFO
            }
        }
    }
    
    Write-Log "" INFO
    if ($success) {
        Write-Log "PHASE COMPLETED SUCCESSFULLY ✓" SUCCESS
    }
    else {
        Write-Log "PHASE FAILED - REVIEW ERRORS ABOVE" ERROR
    }
    
    Write-Log "Log file: $LogFile" INFO
}

# Run main
Main
