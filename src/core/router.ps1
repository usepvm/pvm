

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
            
            Write-Host $msg
        }}
        "list" = [PSCustomObject]@{ command = "pvm list [available [-f]]"; description = "Type 'available' to list installable items. Add '-f' to force reload from source."; action = {
            if ($arguments -contains "available") {
                Get-Available-PHP-Versions -getFromSource ($arguments -contains '-f' -or $arguments -contains '--force')
            } else {
                Display-Installed-PHP-Versions
            }
        }}
        "install" = [PSCustomObject]@{ command = "pvm install <version> [--xdebug] [--dir=/absolute/path/]"; description = "The version must be a specific version. '--xdebug' to include xdebug. '--dir' to specify the installation directory."; action = {
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

            $exitCode = Install-PHP -version $version -customDir $dirValue -includeXDebug ($arguments -contains '--xdebug') -enableOpcache ($arguments -contains '--opcache')
        }}
        "uninstall" = [PSCustomObject]@{ command = "pvm uninstall <version>"; description = "The version must be a specific version."; action = {
            $version = $arguments[0]

            if (-not $version) {
                Write-Host "`nPlease provide a PHP version to uninstall"
                exit 1
            }
            if (-not (Is-Admin)) {
                $arguments = "-ExecutionPolicy Bypass -File `"$PVMEntryPoint`" uninstall `"$version`""
                $process = Start-Process powershell -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru
                $process.WaitForExit()
                $exitCode = $process.ExitCode
            } else {
                $exitCode = Uninstall-PHP -version $version
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
                $exitCode = Update-PHP-Version -variableName $USER_ENV["PHP_CURRENT_ENV_NAME"] -variableValue $version
            }

            Display-Msg-By-ExitCode -msgSuccess "`nNow using PHP $version" -msgError "`nFailed to switch to PHP $version" -exitCode $exitCode
        }}
        "toggle" = [PSCustomObject]@{ command = "pvm toggle [xdebug / opcach]"; description = "Toggle the specified extension on or off."; action = {
            
            $extensionsNames = $arguments
            if (-not $extensionsNames -or $extensionsNames.Count -eq 0) {
                Write-Host "`nPlease specify at least one extension to toggle (xdebug or opcache)."
                exit 1
            }
            $validExtensions = @('xdebug', 'opcache')
            $invalid = $extensionsNames | Where-Object { $_ -notin $validExtensions }
            if ($invalid.Count -gt 0) {
                Write-Host "`nInvalid extension(s) specified: $($invalid -join ', '). Use only 'xdebug' or 'opcache'."
                exit 1
            }

            $result = Toggle-PHP-Extension -extensionsNames $extensionsNames
            
            Write-Host "`nToggled extensions:"
            foreach ($ext in $result.status.Keys) {
                if ($result.status[$ext]) {
                    Write-Host "- $ext is enabled" -ForegroundColor DarkGreen
                } else {
                    Write-Host "- $ext is disabled" -ForegroundColor DarkYellow
                }
            }
            
            Display-Msg-By-ExitCode -msgSuccess "`nExtensions toggled successfully." -msgError "`nFailed to toggle extensions" -exitCode $result.exitCode
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