@echo off
setlocal enabledelayedexpansion

SET FILE_TARGET=%~dp0\src\pvm.ps1

set "ENGINE_OVERRIDE="
set "ARGS=%*"
set "NEW_ARGS="

if /I not "%~1"=="test" goto :skip_shell_parse

set "REST=!ARGS!"

:parse_loop
if not defined REST goto :parse_done

for /f "tokens=1,* delims= " %%A in ("!REST!") do (
    set "TOKEN=%%A"
    set "REST=%%B"
)

if /I "!TOKEN:~0,8!"=="--shell=" (
    set "SHELL_VALUE=!TOKEN:~8!"
    if /I "!SHELL_VALUE!"=="pwsh" (
        set "ENGINE_OVERRIDE=pwsh"
    ) else if /I "!SHELL_VALUE!"=="powershell" (
        set "ENGINE_OVERRIDE=powershell"
    ) else (
        echo Invalid value for --shell: "!SHELL_VALUE!" ^(expected "pwsh" or "powershell"^)
        exit /b 1
    )
) else (
    set "NEW_ARGS=!NEW_ARGS! !TOKEN!"
)

goto :parse_loop

:parse_done
set "ARGS=!NEW_ARGS!"

:skip_shell_parse

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
