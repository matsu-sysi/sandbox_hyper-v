@echo off
setlocal
set "ROOT=%~dp0"
set "LOGBASE=%ROOT%sandbox\logs"
if not exist "%LOGBASE%" mkdir "%LOGBASE%"
set "CMDLOG=%LOGBASE%\launcher-cmd-latest.log"

echo [%date% %time%] start-sandbox.cmd started > "%CMDLOG%"
echo ROOT=%ROOT% >> "%CMDLOG%"
echo LOGBASE=%LOGBASE% >> "%CMDLOG%"
echo. >> "%CMDLOG%"

echo Starting Windows Sandbox launcher...
echo CMD log: %CMDLOG%
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%start-sandbox.ps1" -ForceRestart %* >> "%CMDLOG%" 2>&1
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
echo Launcher completed. Check run log under: %LOGBASE%\YYYY-MM-DD\run-*.log
endlocal
