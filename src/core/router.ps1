
function Invoke-PVMSetup {
    param($arguments)

    $result = @{ code = 0; message = "PVM is already setup" }
    if (-not (Is-PVM-Setup)) {
        $result = Setup-PVM
    }
    $optimized = Optimize-SystemPath
    if ($optimized -ne 0) {
        Write-Host "`nFailed to optimize system path." -ForegroundColor DarkYellow
    }
    
    Display-Msg-By-ExitCode -result $result
    exit 0
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
    
    Write-Host "`nPath: $($result.path)" -ForegroundColor Gray
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
    if ($currentVersion -and ($version -eq $currentVersion)) {
        Read-Host "`nYou are trying to uninstall the currently active PHP version ($version). Press Enter to continue or Ctrl+C to cancel."
    }

    $result = Uninstall-PHP -version $version

    Display-Msg-By-ExitCode -result $result
    exit 0
}

function Invoke-PVMUse {
    param($arguments)
    
    $version = $arguments[0]

    if (-not $version) {
        Write-Host "`nPlease provide a PHP version to use"
        exit 1
    }

    if ($version -eq 'auto') {
        $result = Auto-Select-PHP-Version -version $version
        if ($result.code -ne 0) {
            Display-Msg-By-ExitCode -result $result
            exit 1
        }
        $version = $result.version
    }
    
    $result = Update-PHP-Version -variableName $PHP_CURRENT_ENV_NAME -variableValue $version

    Display-Msg-By-ExitCode -result $result
    exit 0
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

    $result = Set-PHP-Env -name $varName -value $varValue

    Display-Msg-By-ExitCode -result $result
    exit 0
}


function Get-Actions {
    param( $arguments )

    $script:arguments = $arguments
    
    return [ordered]@{
        "setup" = [PSCustomObject]@{
            command = "pvm setup";
            description = "Setup the environment variables and paths for PHP.";
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
            command = "pvm use <version>|[auto]";
            description = "Switch to use the specified version. use 'auto' to switch to the version specified in the current directory’s composer.json or .php-version file.";
            action = { Invoke-PVMUse -arguments $script:arguments }}
        "ini" = [PSCustomObject]@{
            command = "pvm ini <action> [<args>]";
            description = "Manage PHP ini settings. You can use 'set' or 'get' for a setting value; 'status', 'enable' or 'disable' for an extension, or 'restore' the original ini file from backup."; 
            action = { Invoke-PVMIni -arguments $script:arguments }}
        "set" = [PSCustomObject]@{
            command = "pvm set <name> <value>";
            description = "Set a new evironment variable for a PHP version."; 
            action = { Invoke-PVMSet -arguments $script:arguments }}
        "test" = [PSCustomObject]@{
            command = "pvm test";
            description = "Run tests."; 
            action = {
                $verbosityOptions = @('None', 'Normal', 'Detailed', 'Diagnostic')
                $arguments = $arguments | Where-Object {
                    if ($_ -match '^--tag=(.+)$') {
                        $tag = $Matches[1]
                        return $false
                    }
                    return $true
                }
                
                $files = $null
                $verbosity = 'Normal'
                if ($arguments.Count -gt 0 -and $verbosityOptions -contains $arguments[-1]) {
                    $verbosity = $arguments[-1]
                    
                    if ($arguments.Count -gt 1) {
                        $files = $arguments[0..($arguments.Count - 2)]
                    }
                } else {
                    $files = $arguments
                }
                
                Run-Tests -verbosity $verbosity -tests $files -tag $tag
            }}
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