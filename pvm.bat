@echo off
setlocal enabledelayedexpansion

SET FILE_TARGET=%~dp0\src\pvm.ps1

set "ENGINE_OVERRIDE="
set "ARGS=%*"

if /I "%~1"=="test" (
    rem detect via substring-replace: if replacing the flag changes the string, it was present
    if "!ARGS!" NEQ "!ARGS:--pwsh=!" set "ENGINE_OVERRIDE=pwsh"
    if "!ARGS!" NEQ "!ARGS:--powershell=!" set "ENGINE_OVERRIDE=powershell"

    set "ARGS=!ARGS:--powershell=!"
    set "ARGS=!ARGS:--pwsh=!"
)

rem --- handle empty options (same as before) ---
set "ARGS= !ARGS! "
set "ARGS=!ARGS:-- =!"

rem --- pick engine ---
if defined ENGINE_OVERRIDE (
    set "ENGINE=%ENGINE_OVERRIDE%"
) else (
    where pwsh >nul 2>&1
    if !ERRORLEVEL!==0 (
        set "ENGINE=pwsh"
    ) else (
        set "ENGINE=powershell"
    )
)

%ENGINE% -NoProfile -ExecutionPolicy Bypass -File "%FILE_TARGET%" !ARGS!

endlocal
