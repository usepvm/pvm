

param( [string]$operation, [string]$argument1 = $null, [string]$argument2 = $null )

. $PSScriptRoot\options.ps1


if (-not $operation -and $args.Count -eq 0) {
    Write-Host "pvm --help to get the list of commands"
    exit 1
}

$arguments = $args

$actions = [ordered]@{
    "current" = [PSCustomObject]@{ description = "pvm current`t`t`t:`tDisplay active version"; action = { 
        $version = Get-Current-PHP-Version
        if (-not $version) {
            Write-Host "`nSomething went wrong, Check your environment variables !"
            exit 0
        }
        Write-Host "`nRunning version: PHP $version"
    }}
    "list" = [PSCustomObject]@{ description = "pvm list [available [-f]]`t:`tList the PHP installations. 'available' at the end to see what can be installed. '-f' to load from the online source."; action = {
        if ($argument1 -eq "available") {
            if ($arguments -contains '-f') {
                Get-Available-PHP-Versions -getFromSource $true
            } else {
                Get-Available-PHP-Versions
            }
        } else {
            Display-Installed-PHP-Versions
        }
    }}
    "install" = [PSCustomObject]@{ description = "pvm install <version>`t`t:`tThe version can be a specific version"; action = {
        if (-not $argument1) {
            Write-Host "`nPlease provide a PHP version to install"
            exit 1
        }
        Install-PHP -version $argument1
    }}
    "uninstall" = [PSCustomObject]@{ description = "pvm uninstall <version>`t:`tThe version must be a specific version"; action = {
        if (-not $argument1) {
            Write-Host "`nPlease provide a PHP version to uninstall"
            exit 1
        }
        if (-not (Is-Admin)) {
            # Relaunch as administrator with hidden window
            $arguments = "-ExecutionPolicy Bypass -File `"$PSCommandPath`" uninstall `"$argument1`""
            Start-Process powershell -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden
        } else {
            if (Uninstall-PHP -version $argument1) {
                Write-Host "`nPHP $argument1 has been uninstalled successfully"
            } else {
                Write-Host "`nFailed to uninstall PHP $argument1"
            }
        }
    }}
    "use" = [PSCustomObject]@{ description = "pvm use [version]`t`t:`tSwitch to use the specified version"; action = {
        if (-not $argument1) {
            Write-Host "`nPlease provide a PHP version to use"
            exit 1
        }
        if (-not (Is-Admin)) {
            # Relaunch as administrator with hidden window
            $arguments = "-ExecutionPolicy Bypass -File `"$PSCommandPath`" use `"$argument1`""
            Start-Process powershell -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden
        } else {
            Update-PHP-Version -variableName $USER_ENV["PHP_CURRENT_ENV_NAME"] -variableValue $argument1
        }

        Write-Host "`nNow using PHP v$argument1"
    }}
    "set" = [PSCustomObject]@{ description = "pvm set [name] [value]`t:`tset a new evironment variable for a PHP version"; action = {
        if (-not $argument1) {
            Write-Host "`nPlease provide an environment variable name"
            exit 1
        }
        if (-not $argument2) {
            Write-Host "`nPlease provide an environment variable value"
            exit 1
        }          
        if (-not (Is-Admin)) {
            $arguments = "-ExecutionPolicy Bypass -File `"$PSCommandPath`" set `"$argument1`" `"$argument2`""
            Start-Process powershell -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden
        } else {
            Set-PHP-Env -name $argument1 -value $argument2
        }
        Write-Host "`nEnvironment variable '$argument1' set to '$argument2' at the system level."
    }}
}

if (-not $actions.Contains($operation)) {
    $version = Get-Current-PHP-Version
    Write-Host "`nRunning version : $version"
    Write-Host "`nUsage:`n"
    $actions.GetEnumerator() | ForEach-Object {
        $item = $_.Value.description
        Write-Host "  $item"
    }
    exit 1
}

$actions[$operation].action.Invoke()
Write-Host "`n"
