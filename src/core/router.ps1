

function Get-Actions {
    param( $arguments )

    $script:arguments = $arguments
    
    return [ordered]@{
        "setup" = [PSCustomObject]@{ command = "pvm setup [--overwrite-path-backup]"; description = "Setup the environment variables and paths for PHP. Use '--overwrite-path-backup' to overwrite the existing backup of the PATH variable."; action = {

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
        }}
        "current" = [PSCustomObject]@{ command = "pvm current"; description = "Display active version."; action = { 
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
        }}
        "list" = [PSCustomObject]@{ command = "pvm list [available [-f or --force]]"; description = "Type 'available' to list installable items. Add '-f' or '--force' to force reload from source."; action = {
            if ($arguments -contains "available") {
                Get-Available-PHP-Versions -getFromSource ($arguments -contains '-f' -or $arguments -contains '--force')
            } else {
                Display-Installed-PHP-Versions
            }
        }}
        "install" = [PSCustomObject]@{ command = "pvm install <version> [--xdebug] [--opcache] [--dir=/abs/path/]"; description = "The version must be a specific version. '--xdebug/--opcach' to enable xdebug/opcache. '--dir' to specify a custom installation directory."; action = {
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
        }}
        "uninstall" = [PSCustomObject]@{ command = "pvm uninstall <version>"; description = "The version must be a specific version."; action = {
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
        }}
        "use" = [PSCustomObject]@{ command = "pvm use <version>"; description = "Switch to use the specified version."; action = {
            $version = $arguments[0]

            if (-not $version) {
                Write-Host "`nPlease provide a PHP version to use"
                exit 1
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

            Display-Msg-By-ExitCode -msgSuccess "`nNow using PHP $version" -msgError "`nFailed to switch to PHP $version" -exitCode $exitCode
        }}
        "ini" = [PSCustomObject]@{ command = "pvm ini <action> [<args>]"; description = "Manage PHP ini settings. You can use 'set' or 'get' for a setting value; 'status', 'enable' or 'disable' for an extension, or 'restore' the original ini file from backup."; action = {
            $action = $arguments[0]
            if (-not $action) {
                Write-Host "`nPlease specify an action for 'pvm ini'. Use 'set', 'get', 'enable', 'disable' or 'restore'."
                exit 1
            }
            
            $remainingArgs = if ($arguments.Count -gt 1) { $arguments[1..($arguments.Count - 1)] } else { @() }

            $exitCode = Invoke-PVMIni -action $action -params $remainingArgs
        }}
        "set" = [PSCustomObject]@{ command = "pvm set <name> <value>"; description = "Set a new evironment variable for a PHP version."; action = {
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