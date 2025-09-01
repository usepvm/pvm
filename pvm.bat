@echo off
setlocal

rem Run PowerShell with the provided arguments
SET FILE_TARGET=%~dp0\src\pvm.ps1

rem Handle empty options
set "ARGS= %* "
set "ARGS=%ARGS:-- =%"

where pwsh >nul 2>&1
if %ERRORLEVEL%==0 (
    pwsh -ExecutionPolicy Bypass -File "%FILE_TARGET%" %ARGS%
) else (
    powershell -ExecutionPolicy Bypass -File "%FILE_TARGET%" %ARGS%
)

endlocal
