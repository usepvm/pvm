
function Invoke-PVMSetup {

    $result = @{ code = 0; message = "PVM is already setup" }
    if (-not (Is-PVM-Setup)) {
        $result = Setup-PVM
    }
    $optimized = Optimize-SystemPath
    if ($optimized -ne 0) {
        Write-Host "`nFailed to optimize system path." -ForegroundColor DarkYellow
    }
    
    Display-Msg-By-ExitCode -result $result
    return 0
}

function Invoke-PVMCurrent {

    $result = Get-Current-PHP-Version
    if (-not $result.version) {
        Write-Host "`nNo PHP version is currently set. Please use 'pvm use <version>' to set a version."
        return 1
    }
    Write-Host "`nRunning version: PHP $($result.version)"
    
    if (-not $result.status) {
        Write-Host "No status information available for the current PHP version." -ForegroundColor Yellow
        return 1
    }
    
    foreach ($ext in $result.status.Keys) {
        if ($result.status[$ext]) {
            Write-Host "- $ext is enabled" -ForegroundColor DarkGreen
        } else {
            Write-Host "- $ext is disabled" -ForegroundColor DarkYellow
        }
    }
    
    Write-Host "`nPath: $($result.path)" -ForegroundColor Gray
    return 0
}

function Invoke-PVMList{
    param($arguments)
    
    if ($arguments -contains "available") {
        $result = Get-Available-PHP-Versions
    } else {
        $result = Display-Installed-PHP-Versions
    }
    
    return $result
}

function Invoke-PVMInstall {
    param($arguments)
    
    $version = $arguments[0]        
    if (-not $version) {
        Write-Host "`nPlease provide a PHP version to install"
        return 1
    }

    $result = Install-PHP -version $version
    Display-Msg-By-ExitCode -result $result
    return 0
}

function Invoke-PVMUninstall {
    param($arguments)
    
    $version = $arguments[0]

    if (-not $version) {
        Write-Host "`nPlease provide a PHP version to uninstall"
        return 1
    }

    $result = Uninstall-PHP -version $version

    Display-Msg-By-ExitCode -result $result
    return 0
}

function Invoke-PVMUse {
    param($arguments)
    
    $version = $arguments[0]

    if (-not $version) {
        Write-Host "`nPlease provide a PHP version to use"
        return 1
    }

    if ($version -eq 'auto') {
        $result = Auto-Select-PHP-Version
        if ($result.code -ne 0) {
            Display-Msg-By-ExitCode -result $result
            return 1
        }
        $version = $result.version
    }
    
    $result = Update-PHP-Version -variableName $PHP_CURRENT_ENV_NAME -variableValue $version

    Display-Msg-By-ExitCode -result $result
    return 0
}

function Invoke-PVMIni {
    param($arguments)
    
    $action = $arguments[0]
    if (-not $action) {
        Write-Host "`nPlease specify an action for 'pvm ini'. Use 'info', 'set', 'get', 'status', 'enable', 'disable' or 'restore'."
        return 1
    }
    
    $remainingArgs = if ($arguments.Count -gt 1) { $arguments[1..($arguments.Count - 1)] } else { @() }

    $exitCode = Invoke-PVMIniAction -action $action -params $remainingArgs
    return $exitCode
}


function Invoke-PVMTest {
    param($arguments)

    $verbosity = 'Normal'
    $coverage = $false
    $files = $arguments | Where-Object {
        if ($_ -match '^--tag=(.+)$') {
            $tag = $Matches[1]
            return $false
        }
        if ($_ -match '^--coverage$') {
            $coverage = ($_ -eq '--coverage')
            return $false
        }
        if ($_ -match '^--verbosity=(.+)$') {
            $verbosity = $Matches[1]
            return $false
        }
        return $true
    }
    
    $result = Run-Tests -verbosity $verbosity -tests $files -tag $tag -coverage $coverage

    Display-Msg-By-ExitCode -result $result
    return 0
}

function Invoke-PVMLog {
    param($arguments)
    
    
    $pageSizeArg = $arguments | Where-Object { $_ -match '^--pageSize=(.+)$' }
    if ($pageSizeArg) {
        $pageSize = $pageSizeArg -replace '^--pageSize=', ''
    } else {
        $pageSize = $DefaultLogPageSize
    }
    $code = Show-Log -pageSize $pageSize
    return $code
}

function Get-Actions {
    param( $arguments )

    $script:arguments = $arguments
    
    return [ordered]@{
        "setup" = [PSCustomObject]@{
            command = "pvm setup";
            description = "Setup the environment variables and paths for PHP.";
            usage = [ordered]@{
                USAGE = "pvm setup";
                DESCRIPTION = @(
                    "Sets environment variables and config paths for PHP.",
                    "This command should be run once after installation to configure PVM for first use."
                )
            };
            action = { return Invoke-PVMSetup }}
        "current" = [PSCustomObject]@{
            command = "pvm current";
            description = "Display active version.";
            usage = [ordered]@{
                USAGE = "pvm current"
                DESCRIPTION = @(
                    "Shows the currently active PHP version, including the absolute path.",
                    "It also shows the status of xdebug and opcache."
                )
            };
            action = { return Invoke-PVMCurrent }}
        "list" = [PSCustomObject]@{
            command = "pvm list [available]";
            description = "Lists the PHP installations. Type 'available' at the end to see what can be installed.";
            usage = [ordered]@{
                USAGE = "pvm list [available] (alias: pvm ls [available])"
                DESCRIPTION = @(
                    "shows installed PHP versions."
                    "With 'available' argument, shows available PHP versions for installation. (list is cashed for $CacheMaxHours hours)"
                )
                OPTIONS = @(
                    "available .... Show versions available for installation instead of installed versions"
                )
            };
            action = { return Invoke-PVMList -arguments $script:arguments }}
        "install" = [PSCustomObject]@{
            command = "pvm install <version>";
            description = "The version must be a specific version.";
            usage = [ordered]@{
                USAGE = "pvm install <version> (alias: pvm i <version>)"
                DESCRIPTION = @(
                    "Downloads and installs the PHP version, including opcache and xdebug."
                )
                ARGUMENTS = @(
                    "<version> .... The version must be a number e.g. 8, 8.2 or 8.2.0 (required)"
                )
            }
            action = { return Invoke-PVMInstall -arguments $script:arguments }}
        "uninstall" = [PSCustomObject]@{
            command = "pvm uninstall <version>";
            description = "The version must be a specific version.";
            usage = [ordered]@{
                USAGE = "pvm uninstall <version> (alias: pvm rm <version>)"
                DESCRIPTION = @(
                    "Removes the specified PHP version from your system."
                    "The version must be a version number that is currently installed."
                )
                ARGUMENTS = @(
                    "<version> .... The version must be a number e.g. 8, 8.2 or 8.2.0 (required)"
                )
            }
            action = { return Invoke-PVMUninstall -arguments $script:arguments }}
        "use" = [PSCustomObject]@{
            command = "pvm use <version>|[auto]";
            description = "Switch to use the specified version. use 'auto' to switch to the version specified in the current directory's composer.json or .php-version file.";
            usage = [ordered]@{
                USAGE = "pvm use <version> | pvm use auto"
                DESCRIPTION = @(
                    "Switches the active PHP version. You can specify a version number or use 'auto'"
                    "to automatically select the version based on project configuration files."
                )
                EXAMPLES = @(
                    "pvm use 8.2.0 .... Switches to PHP version 8.2.0"
                    "pvm use auto ..... Automatically uses version from composer.json or .php-version file"
                )
                ARGUMENTS = @(
                    "<version> ........ Specific PHP version to use"
                    "auto ............. Auto-detect version from project files"
                )
            }
            action = { return Invoke-PVMUse -arguments $script:arguments }}
        "info" = [PSCustomObject]@{
            command = "pvm info";
            description = "Display information about the environment.";
            usage = [ordered]@{
                USAGE = "pvm info | pvm ini info"
                DESCRIPTION = @(
                    "Displays information about the environment,"
                    "including active PHP version, PHP paths, and extensions."
                )
            }
            action = { $script:arguments = @('info'); return Invoke-PVMIni -arguments $script:arguments }}
        "ini" = [PSCustomObject]@{
            command = "pvm ini <action> [<args>]";
            description = "Manage PHP ini settings. You can use 'set' or 'get' for a setting value; 'status', 'enable' or 'disable' for an extension, 'info' for a summary or 'restore' the original ini file from backup.";
            usage = [ordered]@{
                USAGE = "pvm ini <action> [arguments]"
                DESCRIPTION = @(
                    "Manage PHP configuration (php.ini) settings and extensions for the currently active PHP version."
                )
                ARGUMENTS = @(
                    "set <setting>=<value> ............ Set a php.ini configuration value"
                    "get <setting> .................... Get a php.ini configuration value"
                    "enable <extension> ............... Enable a PHP extension"
                    "disable <extension> .............. Disable a PHP extension"
                    "status <extension> ............... Check if extension is enabled"
                    "info ............................. Displays information about the environment and php.ini information summary"
                    "restore .......................... Restore original php.ini from backup"
                    
                )
                EXAMPLES = @(
                    "pvm ini set memory_limit=256M .... Sets memory limit to 256MB"
                    "pvm ini get memory_limit ......... Shows current memory limit setting"
                    "pvm ini enable mysqli ............ Enables the mysqli extension"
                    "pvm ini disable xdebug ........... Disables the xdebug extension"
                    "pvm ini status opcache ........... Shows if opcache extension is enabled"
                )
            }
            action = { return Invoke-PVMIni -arguments $script:arguments }}
        "test" = [PSCustomObject]@{
            command = "pvm test";
            description = "Run tests.";
            usage = [ordered]@{
                USAGE = "pvm test [files] [--coverage] [--verbosity=<verbosity>] [--tag=<tag>]"
                DESCRIPTION = @(
                    "Runs the PVM test suite to verify that the installation and configuration"
                    "are working correctly. This includes testing PHP version switching,"
                    "path resolution, and core functionality."
                )
                EXAMPLES = @(
                    "pvm test ......................... Runs all tests with Normal (default) verbosity"
                    "pvm test use install ............. Runs only use.tests.ps1 and install.tests.ps1 with Normal verbosity."
                    "pvm test --verbosity=Detailed .... Runs all tests with Detailed verbosity."
                    "pvm test --coverage .............. Runs all tests and generates coverage report."
                    "pvm test --tag=unit .............. Runs only tests with tag 'unit'"
                )
                ARGUMENTS = @(
                    "files ............................ Run only specific test files (e.g. use, install)"
                )
                OPTIONS = @(
                    "--coverage ....................... Generate coverage report"
                    "--verbosity=<verbosity> .......... Set verbosity level (None, Normal (Default), Detailed, Diagnostic)"
                    "--tag=<tag> ...................... Run only tests with specific tag"
                )
            }
            action = { return Invoke-PVMTest -arguments $script:arguments }}
        "log" = [PSCustomObject]@{
            command = "pvm log";
            description = "Display the log file.";
            usage = [ordered]@{
                USAGE = "pvm log --pageSize=[number] (default is $DefaultLogPageSize)"
                DESCRIPTION = @(
                    "Displays the PVM log file contents, showing recent errors,"
                    "and system messages. Useful for troubleshooting issues."
                )
                EXAMPLES = @(
                    "pvm log .................. Shows the last $DefaultLogPageSize entries of the log file"
                    "pvm log --pageSize=50 .... Shows the last 50 entries of the log file"
                )
            }
            action = { return Invoke-PVMLog -arguments $script:arguments }}
    }
}


