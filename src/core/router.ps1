
function Invoke-PVMSetup {
    param($arguments)

    $shouldOverwrite = ($arguments -contains '--overwrite-path-backup')
    $overwritePathBackup = $arguments[0]

    $output = 0
    if (-not (Is-Admin)) {
        $arguments = "-ExecutionPolicy Bypass -File `"$PVMEntryPoint`" setup `"$overwritePathBackup`""
        $process = Start-Process powershell -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru
        $process.WaitForExit()
        $exitCode = $process.ExitCode
    } else {
        $exitCode = 1
        if (-not (Is-PVM-Setup)) {
            $exitCode = Setup-PVM
            if ($exitCode -eq 0) {
                $output = Optimize-SystemPath -shouldOverwrite $shouldOverwrite
            }
        }
    }
    
    if ($output -eq 0) {
        Write-Host "`nOriginal PATH variable saved to $PATH_VAR_BACKUP_PATH"
    } else {
        Write-Host "`nFailed to log the original PATH variable."
    }
    
    if ($exitCode -eq 1) {
        Write-Host "`nPATH already contains PVM and PHP environment reference."
        exit $exitCode
    } else {
        Display-Msg-By-ExitCode -msgSuccess "`nPVM has been setup successfully" -msgError "`nFailed to setup PVM" -exitCode $exitCode
    }
}

function Invoke-PVMCurrent {
    param($arguments)

    $result = Get-Current-PHP-Version
    if (-not $result.version) {
        Write-Host "`nNo PHP version is currently set. Please use 'pvm use <version>' to set a version."
        exit 1
    }
    Write-Host "`nRunning version: PHP $($result.version)"
    
    if (-not $result.status) {
        Write-Host "No status information available for the current PHP version." -ForegroundColor Yellow
        exit 1
    }
    
    foreach ($ext in $result.status.Keys) {
        if ($result.status[$ext]) {
            Write-Host "- $ext is enabled" -ForegroundColor DarkGreen
        } else {
            Write-Host "- $ext is disabled" -ForegroundColor DarkYellow
        }
    }
    
    Write-Host "`nPath: $($result.path)" -ForegroundColor DarkCyan
}

function Invoke-PVMList{
    param($arguments)
    
    if ($arguments -contains "available") {
        $result = Get-Available-PHP-Versions -getFromSource ($arguments -contains '-f' -or $arguments -contains '--force')
    } else {
        $result = Display-Installed-PHP-Versions
    }
}

function Invoke-PVMInstall {
    param($arguments)
    
    $version = $arguments[0]        
    if (-not $version) {
        Write-Host "`nPlease provide a PHP version to install"
        exit 1
    }

    $dirArg = $arguments | Where-Object { $_ -like '--dir=*' }
    if ($null -ne $dirArg) {
        $dirValue = $dirArg -replace '^--dir=', ''
        if (-not $dirValue) {
            Write-Host "`nPlease provide a directory to install PHP. Use '--dir=<path>' to specify the directory."
            exit 1
        }
    }

    $includeXDebug = ($arguments -contains '--xdebug')
    $enableOpcache = ($arguments -contains '--opcache')
    $exitCode = Install-PHP -version $version -customDir $dirValue -includeXDebug $includeXDebug -enableOpcache $enableOpcache
}

function Invoke-PVMUninstall {
    param($arguments)
    
    $version = $arguments[0]

    if (-not $version) {
        Write-Host "`nPlease provide a PHP version to uninstall"
        exit 1
    }

    $currentVersion = (Get-Current-PHP-Version).version
    $shouldRemoveCurrent = ($arguments -contains '--skip-confirmation')
    if ((-not $shouldRemoveCurrent) -and ($currentVersion -and ($version -eq $currentVersion))) {
        Read-Host "`nYou are trying to uninstall the currently active PHP version ($version). Press Enter to continue or Ctrl+C to cancel."
    }

    if (-not (Is-Admin)) {
        $arguments = "-ExecutionPolicy Bypass -File `"$PVMEntryPoint`" uninstall `"$version`" --skip-confirmation"
        $process = Start-Process powershell -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru
        $process.WaitForExit()
        $exitCode = $process.ExitCode
    } else {
        $exitCode = Uninstall-PHP -version $version
    }

    if ($exitCode -eq -2) {
        Write-Host "`nPHP version $version is not installed."
        exit $exitCode
    }

    Display-Msg-By-ExitCode -msgSuccess "`nPHP $version has been uninstalled successfully" -msgError "`nFailed to uninstall PHP $version" -exitCode $exitCode
}

function Invoke-PVMUse {
    param($arguments)
    
    $version = $arguments[0]

    if (-not $version) {
        Write-Host "`nPlease provide a PHP version to use"
        exit 1
    }

    if ($version -eq 'auto') {
        $version = Detect-PHP-VersionFromProject
        
        if (-not $version) {
            Write-Host "`nCould not detect PHP version from .php-version or composer.json"
            exit 1
        }
        
        if (-not (Is-PHP-Version-Installed -version $version)) {
            Write-Host "`nDetected PHP version '$version' from project, but it is not installed."
            Write-Host "Run: pvm install $version"
            exit 1
        }
        Write-Host "`nDetected PHP version from project: $version"
    }
    
    if (-not (Is-Admin)) {
        # Relaunch as administrator with hidden window
        $arguments = "-ExecutionPolicy Bypass -File `"$PVMEntryPoint`" use `"$version`""
        $process = Start-Process powershell -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru
        $process.WaitForExit()
        $exitCode = $process.ExitCode
    } else {
        $exitCode = Update-PHP-Version -variableName $PHP_CURRENT_ENV_NAME -variableValue $version
    }

    Display-Msg-By-ExitCode -msgSuccess "`nNow using PHP $version" -msgError "`nNo matching PHP versions found for '$version', Use 'pvm list' to see installed versions." -exitCode $exitCode
}

function Detect-PHP-VersionFromProject {
    
    try {
        # 1. Check .php-version
        if (Test-Path ".php-version") {
            $version = Get-Content ".php-version" | Select-Object -First 1
            return $version.Trim()
        }

        # 2. Check composer.json
        if (Test-Path "composer.json") {
            try {
                $json = Get-Content "composer.json" -Raw | ConvertFrom-Json
                if ($json.require.php) {
                    $constraint = $json.require.php.Trim()
                    # Extract first PHP version number in the string (e.g. from "^8.3" or ">=8.1 <8.3")
                    if ($constraint -match "(\d+\.\d+(\.\d+)?)") {
                        return $matches[1]
                    }
                }
            } catch {
                Write-Host "`nFailed to parse composer.json: $_"
            }
        }
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Detect-PHP-VersionFromProject: Failed to detect PHP version from project" -data $_.Exception.Message
    }

    return $null
}



function Invoke-PVMIni {
    param($arguments)
    
    $action = $arguments[0]
    if (-not $action) {
        Write-Host "`nPlease specify an action for 'pvm ini'. Use 'set', 'get', 'enable', 'disable' or 'restore'."
        exit 1
    }
    
    $remainingArgs = if ($arguments.Count -gt 1) { $arguments[1..($arguments.Count - 1)] } else { @() }

    $exitCode = Invoke-PVMIniAction -action $action -params $remainingArgs
}

function Invoke-PVMSet {
    param($arguments)
    
    $varName = $arguments[0]
    $varValue = $arguments[1]
    
    if (-not $varName) {
        Write-Host "`nPlease provide an environment variable name"
        exit 1
    }
    if (-not $varValue) {
        Write-Host "`nPlease provide an environment variable value"
        exit 1
    }          
    if (-not (Is-Admin)) {
        $arguments = "-ExecutionPolicy Bypass -File `"$PVMEntryPoint`" set `"$varName`" `"$varValue`""
        $process = Start-Process powershell -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru
        $process.WaitForExit()
        $exitCode = $process.ExitCode
    } else {
        $exitCode = Set-PHP-Env -name $varName -value $varValue
    }

    Display-Msg-By-ExitCode -msgSuccess "`nEnvironment variable '$varName' set to '$varValue' at the system level." -msgError "`nFailed to set environment variable '$varName'" -exitCode $exitCode
}


function Get-Actions {
    param( $arguments )

    $script:arguments = $arguments
    
    return [ordered]@{
        "setup" = [PSCustomObject]@{
            command = "pvm setup [--overwrite-path-backup]";
            description = "Setup the environment variables and paths for PHP. Use '--overwrite-path-backup' to overwrite the existing backup of the PATH variable.";
            action = { Invoke-PVMSetup -arguments $script:arguments }}
        "current" = [PSCustomObject]@{
            command = "pvm current";
            description = "Display active version.";
            action = { Invoke-PVMCurrent -arguments $script:arguments }}
        "list" = [PSCustomObject]@{
            command = "pvm list [available [-f or --force]]";
            description = "Type 'available' to list installable items. Add '-f' or '--force' to force reload from source."; 
            action = { Invoke-PVMList -arguments $script:arguments }}
        "install" = [PSCustomObject]@{
            command = "pvm install <version> [--xdebug] [--opcache] [--dir=/abs/path/]";
            description = "The version must be a specific version. '--xdebug/--opcach' to enable xdebug/opcache. '--dir' to specify a custom installation directory.";
            action = { Invoke-PVMInstall -arguments $script:arguments }}
        "uninstall" = [PSCustomObject]@{
            command = "pvm uninstall <version>";
            description = "The version must be a specific version."; 
            action = { Invoke-PVMUninstall -arguments $script:arguments }}
        "use" = [PSCustomObject]@{
            command = "pvm use <version>";
            description = "Switch to use the specified version.";
            action = { Invoke-PVMUse -arguments $script:arguments }}
        "ini" = [PSCustomObject]@{
            command = "pvm ini <action> [<args>]";
            description = "Manage PHP ini settings. You can use 'set' or 'get' for a setting value; 'status', 'enable' or 'disable' for an extension, or 'restore' the original ini file from backup."; 
            action = { Invoke-PVMIni -arguments $script:arguments }}
        "set" = [PSCustomObject]@{
            command = "pvm set <name> <value>";
            description = "Set a new evironment variable for a PHP version."; 
            action = { Invoke-PVMSet -arguments $script:arguments }}
    }
}

function Show-Usage {
    $version = (Get-Current-PHP-Version).version
    if ($version) {
        Write-Host "`nRunning version : $version"
    }
    Write-Host "`nUsage:`n"
    $maxLineLength = 70
    $actions.GetEnumerator() | ForEach-Object {
        $dotsCount = $maxLineLength - $_.Value.command.Length
        if ($dotsCount -lt 0) { $dotsCount = 0 }
        $dots = '.' * $dotsCount
        Write-Host "$($_.Value.command) $dots $($_.Value.description)"
    }
}