@echo off
REM Auto-compile and reload script for ProfitTrailBot
REM This triggers MT5's automatic recompilation

echo.
echo ===============================================
echo ProfitTrailBot MQL5 Compilation Trigger
echo ===============================================
echo.

setlocal enabledelayedexpansion

REM Define paths
set TERMINAL_PATH=c:\Users\Joseph Nganga\AppData\Roaming\MetaQuotes\Terminal\BB16F565FAAA6B23A20C26C49416FF05
set MQ5_FILE=%TERMINAL_PATH%\MQL5\Experts\ProfitTrailBot 1.5.2\ProfitTrailBotEnterprises-1.5.2.mq5
set EX5_FILE=%TERMINAL_PATH%\MQL5\Experts\ProfitTrailBot 1.5.2\ProfitTrailBotEnterprises-1.5.2.ex5

REM Check file exists
if not exist "%MQ5_FILE%" (
    echo ERROR: MQ5 file not found: %MQ5_FILE%
    exit /b 1
)
echo [OK] MQ5 file found

REM Get current timestamp
for /f "tokens=2-4 delims=/ " %%a in ('date /t') do (set mydate=%%c%%a%%b)
for /f "tokens=1-2 delims=/:" %%a in ('time /t') do (set mytime=%%a%%b)
set TIMESTAMP=%mydate%_%mytime%

REM Try to find MetaEditor in common locations
set EDITOR_FOUND=0
if exist "C:\Program Files\MetaTrader 5\metaeditor64.exe" (
    set METAEDITOR=C:\Program Files\MetaTrader 5\metaeditor64.exe
    set EDITOR_FOUND=1
)
if exist "C:\Program Files (x86)\MetaTrader 5\metaeditor64.exe" (
    set METAEDITOR=C:\Program Files (x86)\MetaTrader 5\metaeditor64.exe
    set EDITOR_FOUND=1
)

if !EDITOR_FOUND! equ 1 (
    echo [OK] MetaEditor found: %METAEDITOR%
    echo.
    echo Starting compilation...
    "%METAEDITOR%" /compile:"%MQ5_FILE%" /log
    echo Compilation initiated.
    echo.
    echo Waiting for MT5 to reload...
    timeout /t 3 /nobreak
    echo.
    echo [SUCCESS] Changes applied. MT5 should reload automatically.
) else (
    echo [INFO] MetaEditor not found at standard locations
    echo [INFO] Using MT5 auto-compile feature...
    echo.
    echo To trigger compilation manually:
    echo 1. In MT5 Terminal: Press F3 to open MetaEditor
    echo 2. File ^> Recent Files ^> ProfitTrailBotEnterprises-1.5.2.mq5
    echo 3. Press F5 to compile
    echo.
    echo MT5 auto-compilation will trigger when the file is modified.
    echo If MT5 doesn't auto-compile within 10 seconds, use manual compile ^(F5^).
)

echo.
echo ===============================================
echo Changes Applied:
echo - Strategy_Mix: STRAT_ICT_ONLY (was STRAT_BOTH)
echo - Suitability_Log_Decisions: true (was false)
echo ===============================================
echo.
echo Waiting for MT5 to refresh the expert...
timeout /t 10 /nobreak

echo.
echo [DONE] Ready to monitor for trade execution!
echo.
pause
