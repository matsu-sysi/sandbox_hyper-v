@echo off
setlocal
set "ROOT=%~dp0"
set "LOGBASE=%ROOT%sandbox\logs"
if not exist "%LOGBASE%" mkdir "%LOGBASE%"
set "CMDLOG=%LOGBASE%\launcher-cmd-latest.log"
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "RUNID=%%i"
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set "LOGDATE=%%i"
set "LOGDIR=%LOGBASE%\%LOGDATE%"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
set "RUNLOG=%LOGDIR%\run-%RUNID%.log"
set "STATUSLOG=%LOGDIR%\status-%RUNID%.log"

echo [%date% %time%] start-sandbox.cmd started > "%CMDLOG%"
echo ROOT=%ROOT% >> "%CMDLOG%"
echo LOGBASE=%LOGBASE% >> "%CMDLOG%"
echo RUNID=%RUNID% >> "%CMDLOG%"
echo RUNLOG=%RUNLOG% >> "%CMDLOG%"
echo STATUSLOG=%STATUSLOG% >> "%CMDLOG%"
echo. >> "%CMDLOG%"

echo Starting Windows Sandbox launcher...
echo CMD log   : %CMDLOG%
echo Run log   : %RUNLOG%
echo Status log: %STATUSLOG%
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%start-sandbox.ps1" -RunId "%RUNID%" -LogDate "%LOGDATE%" -ForceRestart %* >> "%CMDLOG%" 2>&1
set "RC=%ERRORLEVEL%"
echo. >> "%CMDLOG%"
echo [%date% %time%] exit code: %RC% >> "%CMDLOG%"

if not "%RC%"=="0" (
  echo.
  echo Start-Sandbox failed. See log:
  echo   %CMDLOG%
  pause
  endlocal
  exit /b %RC%
)

echo Launcher completed. Waiting bootstrap status (max 20s)...
set /a WAIT=0
:wait_loop
if exist "%STATUSLOG%" (
  type "%STATUSLOG%"
  goto done_wait
)
set /a WAIT+=1
if %WAIT% GEQ 20 goto done_wait
ping -n 2 127.0.0.1 >nul
goto wait_loop
:done_wait
echo If tools are still installing, check:
echo   %STATUSLOG%
endlocal
