
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
        return -1
    }
    Write-Host "`nRunning version: PHP $($result.version)"
    
    if (-not $result.status) {
        Write-Host "No status information available for the current PHP version." -ForegroundColor Yellow
        return -1
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
    
    $term = ($arguments | Where-Object { $_ -match '^--search=(.+)$' }) -replace '^--search=', ''
    $result = Get-PHP-Versions-List -available ($arguments -contains "available") -term $term
    
    return $result
}

function Invoke-PVMInstall {
    param($arguments)
    
    $version = $arguments[0]

    if ($version -eq 'auto') {
        $result = Auto-Select-PHP-Version

        if ($result.code -eq 0) {
            $version = $result.version
            Display-Msg-By-ExitCode -result $result -message "php $version is already installed!"
            return -1
        }

        $version = $result.version
    }

    if (-not $version) {
        Write-Host "`nPlease provide a PHP version to install"
        return -1
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
        return -1
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
        return -1
    }

    if ($version -eq 'auto') {
        $result = Auto-Select-PHP-Version
        if ($result.code -ne 0) {
            Display-Msg-By-ExitCode -result $result
            return -1
        }
        $version = $result.version
    }
    
    $result = Update-PHP-Version -version $version

    Display-Msg-By-ExitCode -result $result
    return 0
}

function Invoke-PVMIni {
    param($arguments)
    
    $action = $arguments[0]
    if (-not $action) {
        Write-Host "`nPlease specify an action for 'pvm ini'. Use 'info', 'set', 'get', 'status', 'enable', 'disable', 'install', 'list' or 'restore'."
        return -1
    }
    
    $remainingArgs = if ($arguments.Count -gt 1) { $arguments[1..($arguments.Count - 1)] } else { @() }

    $exitCode = Invoke-PVMIniAction -action $action -params $remainingArgs
    return $exitCode
}


function Invoke-PVMTest {
    param($arguments)

    $options = @{
        verbosity = 'Normal'
        coverage = $false
        tag = $null
        target = 75
    }
    $files = $arguments | Where-Object {
        if ($_ -match '^--tag=(.+)$') {
            $options.tag = $Matches[1]
            return $false
        }
        if ($_ -match '^--coverage(?:=(\d+(?:\.\d+)?))?$') {
            $options.coverage = $true
            if ($Matches[1]) {
                $options.target = [decimal] $Matches[1]
            }
            return $false
        }
        if ($_ -match '^--verbosity=(.+)$') {
            $options.verbosity = $Matches[1]
            return $false
        }
        return $true
    }
    
    return Run-Tests -tests $files -options $options
}

function Invoke-PVMLog {
    param($arguments)
    
    $pageSizeArg = $arguments | Where-Object { $_ -match '^--pageSize=(.+)$' }
    if ($pageSizeArg) {
        $pageSize = $pageSizeArg -replace '^--pageSize=', ''
    } else {
        $pageSize = $DEFAULT_LOG_PAGE_SIZE
    }

    $term = ($arguments | Where-Object { $_ -match '^--search=(.+)$' }) -replace '^--search=', ''
    $code = Show-Log -pageSize $pageSize -term $term
    return $code
}

function Invoke-PVMHelp {
    param($arguments)
    
    $command = $arguments[0]
    if ($command) {
        $usage = $actions[$command].usage
        if ($null -eq $usage) {
            Write-Host "`nNo usage information available for the '$operation' operation." -ForegroundColor Yellow
            return -1
        }
        foreach ($key in $usage.Keys) {
            Write-Host "`n$key`:" -ForegroundColor Cyan
            if($usage[$key] -is [array]) {
                $($usage.$key) | ForEach-Object { Write-Host "  $_" }
            } else {
                Write-Host "  $($usage[$key])"
            }
        }
    } else {
        Show-Usage
    }
    
    return 0
}

function Invoke-PVMProfile {
    param($arguments)
    
    $action = $arguments[0]
    
    if (-not $action) {
        Write-Host "`nPlease specify an action for 'pvm profile'. Use 'save', 'load', 'list', 'show', 'delete', 'export', or 'import'." -ForegroundColor Yellow
        return -1
    }
    
    $remainingArgs = if ($arguments.Count -gt 1) { $arguments[1..($arguments.Count - 1)] } else { @() }
    
    switch ($action.ToLower()) {
        "save" {
            if ($remainingArgs.Count -eq 0) {
                Write-Host "`nPlease provide a profile name: pvm profile save <name> [description]" -ForegroundColor Yellow
                return -1
            }
            $profileName = if ($remainingArgs.Count -gt 1) { $remainingArgs[0] } else { $remainingArgs }
            $description = if ($remainingArgs.Count -gt 1) { ($remainingArgs[1..($remainingArgs.Count - 1)] -join ' ') } else { $null }
            return (Save-PHP-Profile -profileName $profileName -description $description)
        }
        "load" {
            if ($remainingArgs.Count -eq 0) {
                Write-Host "`nPlease provide a profile name: pvm profile load <name>" -ForegroundColor Yellow
                return -1
            }
            $profileName = if ($remainingArgs.Count -gt 1) { $remainingArgs[0] } else { $remainingArgs }
            return (Load-PHP-Profile -profileName $profileName)
        }
        "list" {
            return (List-PHP-Profiles)
        }
        "show" {
            if ($remainingArgs.Count -eq 0) {
                Write-Host "`nPlease provide a profile name: pvm profile show <name>" -ForegroundColor Yellow
                return -1
            }
            $profileName = if ($remainingArgs.Count -gt 1) { $remainingArgs[0] } else { $remainingArgs }
            
            return (Show-PHP-Profile -profileName $profileName)
        }
        "delete" {
            if ($remainingArgs.Count -eq 0) {
                Write-Host "`nPlease provide a profile name: pvm profile delete <name>" -ForegroundColor Yellow
                return -1
            }
            
            $profileName = if ($remainingArgs.Count -gt 1) { $remainingArgs[0] } else { $remainingArgs }
            
            return (Delete-PHP-Profile -profileName $profileName)
        }
        "export" {
            if ($remainingArgs.Count -eq 0) {
                Write-Host "`nPlease provide a profile name: pvm profile export <name> [path]" -ForegroundColor Yellow
                return -1
            }
            
            $profileName = if ($remainingArgs.Count -gt 1) { $remainingArgs[0] } else { $remainingArgs }
            $exportPath = if ($remainingArgs.Count -gt 1) { $remainingArgs[1] } else { $null }
            
            return (Export-PHP-Profile -profileName $profileName -exportPath $exportPath)
        }
        "import" {
            if ($remainingArgs.Count -eq 0) {
                Write-Host "`nPlease provide a file path: pvm profile import <path> [name]" -ForegroundColor Yellow
                return -1
            }
            $importPath = if ($remainingArgs.Count -gt 1) { $remainingArgs[0] } else { $remainingArgs }
            $profileName = if ($remainingArgs.Count -gt 1) { $remainingArgs[1] } else { $null }
            
            return (Import-PHP-Profile -importPath $importPath -profileName $profileName)
        }
        default {
            Write-Host "`nUnknown action '$action'. Use 'save', 'load', 'list', 'show', 'delete', 'export', or 'import'." -ForegroundColor Yellow
            return -1
        }
    }
}

function Get-Actions {
    param( $arguments )

    $script:arguments = $arguments
    
    return [ordered]@{
        "help" = [PSCustomObject]@{
            command = "pvm help [command]";
            description = "Display help for a command.";
            usage = [ordered]@{
                USAGE = "pvm help [command]";
                DESCRIPTION = @(
                    "Displays help for a command.",
                    "If no command is provided, displays help for all commands."
                );
            };
            action = { return Invoke-PVMHelp -arguments $script:arguments }}
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
                USAGE = "pvm list [available] [--search=<term>] (alias: pvm ls [available] [--search=<term>])"
                DESCRIPTION = @(
                    "shows installed PHP versions."
                    "With 'available' argument, shows available PHP versions for installation. (list is cashed for $CACHE_MAX_HOURS hours)"
                )
                EXAMPLES = @(
                    "pvm list ........................... Show installed versions"
                    "pvm list available ................. Show versions available for installation instead of installed versions"
                    "pvm list --search=8.2 .............. Show installed versions with 8.2 in the name"
                    "pvm list available --search=8.2 .... Show available versions with 8.2 in the name"
                )
            };
            action = { return Invoke-PVMList -arguments $script:arguments }}
        "install" = [PSCustomObject]@{
            command = "pvm install <version>|[auto]";
            description = "The version must be a specific version. use 'auto' to install the version specified in the current directory's composer.json or .php-version file.";
            usage = [ordered]@{
                USAGE = "pvm install <version> (alias: pvm i <version>) | pvm install auto"
                DESCRIPTION = @(
                    "Downloads and installs the PHP version, including opcache and xdebug."
                    "or use 'auto' to automatically select the version based on project configuration files."
                )
                ARGUMENTS = @(
                    "<version> .... The version must be a number e.g. 8, 8.2 or 8.2.0 (required)"
                    "auto ......... Auto-detect version from project files"
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
            action = { $script:arguments = @('info') + $script:arguments; return Invoke-PVMIni -arguments $script:arguments }}
        "ini" = [PSCustomObject]@{
            command = "pvm ini <action> [<args>]";
            description = "Manage PHP ini settings. You can use 'set' or 'get' for a setting value; 'status', 'install', 'list [available]', 'enable' or 'disable' for an extension, 'info' for a summary or 'restore' the original ini file from backup.";
            usage = [ordered]@{
                USAGE = "pvm ini <action> [arguments]"
                DESCRIPTION = @(
                    "Manage PHP configuration (php.ini) settings and extensions for the currently active PHP version."
                )
                ARGUMENTS = @(
                    "set <setting>=<value> [--disable] ................. Set a php.ini configuration value"
                    "get <setting> ..................................... Get a php.ini configuration value"
                    "enable <extension> ................................ Enable a PHP extension"
                    "disable <extension> ............................... Disable a PHP extension"
                    "status <extension> ................................ Check if extension is enabled"
                    "info [extensions] [settings] [--search=<term>] .... Displays information about the environment and php.ini information summary"
                    "restore ........................................... Restore original php.ini from backup"
                    "install <extension> ............................... Install a PHP extension"
                    "list [available] [--search=<term>] ................ Lists the PHP extensions. Type 'available' at the end to see what can be installed."
                )
                EXAMPLES = @(
                    "pvm ini set memory_limit=256M ..................... Sets memory limit to 256MB and enables the setting"
                    "pvm ini set opcache.enable=1 --disable ............ Sets opcache.enable to 1 and disables the setting"
                    "pvm ini set memory=1G ............................. Shows matching settings for 'memory' then prompts for value and enables the setting"
                    "pvm ini set memory ................................ Shows matching settings for 'memory' then prompts for value and enables the setting"
                    "pvm ini get memory_limit .......................... Shows current memory limit setting"
                    "pvm ini get memory...... .......................... Shows matching settings for 'memory' setting"
                    "pvm ini enable mysqli ............................. Enables the mysqli extension"
                    "pvm ini enable sql ................................ Shows matching extensions for 'sql' then enables the chosen one"
                    "pvm ini disable xdebug ............................ Disables the xdebug extension"
                    "pvm ini disable sql ............................... Shows matching extensions for 'sql' then disables the chosen one"
                    "pvm ini status opcache ............................ Shows opcache extension status"
                    "pvm ini status sql ................................ Shows matching extensions status for 'sql'"
                    "pvm ini info ...................................... Lists php.ini settings and extensions"
                    "pvm ini info --search=cache ....................... Lists php.ini settings and extensions with 'cache' in their name"
                    "pvm ini info extensions ........................... Lists php.ini extensions only"
                    "pvm ini info settings ............................. Lists php.ini settings only"
                    "pvm ini install opcache ........................... Installs the opcache extension"
                    "pvm ini list ...................................... Lists the PHP extensions"
                    "pvm ini list available ............................ Lists available PHP extensions"
                    "pvm ini list --search=zip ......................... Lists PHP extensions with 'zip' in their name"
                    "pvm ini list available --search=zip ............... Lists available PHP extensions with 'zip' in their name"
                )
            }
            action = { return Invoke-PVMIni -arguments $script:arguments }}
        "profile" = [PSCustomObject]@{
            command = "pvm profile <action> [<args>]";
            description = "Manage PHP configuration profiles. Save, load, and share popular PHP settings and extensions.";
            usage = [ordered]@{
                USAGE = "pvm profile <action> [arguments]"
                DESCRIPTION = @(
                    "Manage PHP configuration profiles stored as JSON files.",
                    "Profiles contain popular/common PHP settings and extension states that can be saved and loaded.",
                    "Only popular/common settings and extensions are included. Other settings/extensions can be added manually using 'pvm ini' commands."
                )
                ARGUMENTS = @(
                    "save <name> [description] .................... Save current PHP configuration to a profile"
                    "load <name> .................................. Load and apply a saved profile"
                    "list ......................................... List all available profiles"
                    "show <name> .................................. Show detailed profile contents"
                    "delete <name> ................................ Delete a profile"
                    "export <name> [path] ......................... Export profile to a JSON file"
                    "import <path> [name] ......................... Import profile from a JSON file"
                )
                EXAMPLES = @(
                    "pvm profile save development ................. Saves current config as 'development' profile"
                    "pvm profile save production 'Prod config' .... Saves with description"
                    "pvm profile load development ................. Applies 'development' profile to current PHP"
                    "pvm profile list ............................. Lists all saved profiles"
                    "pvm profile show development ................. Shows detailed profile information"
                    "pvm profile delete old-profile ............... Deletes a profile"
                    "pvm profile export development ............... Exports profile to current directory"
                    "pvm profile export dev ./backup.json ......... Exports to specific path"
                    "pvm profile import ./my-profile.json ......... Imports profile from file"
                    "pvm profile import ./profile.json custom ..... Imports with custom name"
                )
            }
            action = { return Invoke-PVMProfile -arguments $script:arguments }}
        "log" = [PSCustomObject]@{
            command = "pvm log";
            description = "Display the log file.";
            usage = [ordered]@{
                USAGE = "pvm log --pageSize=[number] (default is $DEFAULT_LOG_PAGE_SIZE)"
                DESCRIPTION = @(
                    "Displays the PVM log file contents, showing recent errors,"
                    "and system messages. Useful for troubleshooting issues."
                )
                EXAMPLES = @(
                    "pvm log .................. Shows the last $DEFAULT_LOG_PAGE_SIZE entries of the log file"
                    "pvm log --pageSize=50 .... Shows the last 50 entries of the log file"
                )
            }
            action = { return Invoke-PVMLog -arguments $script:arguments }}
        "test" = [PSCustomObject]@{
            command = "pvm test";
            description = "Run tests.";
            usage = [ordered]@{
                USAGE = "pvm test [files] [--coverage[=<number>]] [--verbosity=<verbosity>] [--tag=<tag>]"
                DESCRIPTION = @(
                    "Runs the PVM test suite to verify that the installation and configuration"
                    "are working correctly. This includes testing PHP version switching,"
                    "path resolution, and core functionality."
                )
                EXAMPLES = @(
                    "pvm test ......................... Runs all tests with Normal (default) verbosity"
                    "pvm test use install ............. Runs only use.tests.ps1 and install.tests.ps1 with Normal verbosity."
                    "pvm test --verbosity=Detailed .... Runs all tests with Detailed verbosity."
                    "pvm test --coverage .............. Runs all tests and generates coverage report (target: 75%)"
                    "pvm test --coverage=80 ........... Runs all tests and generates coverage report (target: 80%)"
                    "pvm test --tag=unit .............. Runs only tests with tag 'unit'"
                )
                ARGUMENTS = @(
                    "files ............................ Run only specific test files (e.g. use, install)"
                )
                OPTIONS = @(
                    "--coverage[=<number>] ............ Generate coverage report with optional target percentage (default: 75%)"
                    "--verbosity=<verbosity> .......... Set verbosity level (None, Normal (Default), Detailed, Diagnostic)"
                    "--tag=<tag> ...................... Run only tests with specific tag"
                )
            }
            action = { return Invoke-PVMTest -arguments $script:arguments }}
    }
}


