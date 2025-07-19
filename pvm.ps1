

param( [string]$operation )

. $PSScriptRoot\options.ps1


if (-not $operation -and $args.Count -eq 0) {
    Write-Host "pvm --help to get the list of commands"
    exit 1
}

$arguments = $args

$actions = [ordered]@{
    "setup" = [PSCustomObject]@{ description = "pvm setup / Setup the environment variables and paths for PHP."; action = {
        # check if running as admin
        if (-not (Is-Admin)) {
            # Relaunch as administrator with hidden window
            $arguments = "-ExecutionPolicy Bypass -File `"$PSCommandPath`" setup"
            $process = Start-Process powershell -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru
            $process.WaitForExit()
            $exitCode = $process.ExitCode
        } else {
            $exitCode = Setup-PVM
        }

        if ($exitCode -eq 2) {
            Write-Host "`nPATH already contains PVM and PHP environment reference."
            exit $exitCode
        } else {
            Display-Msg-By-ExitCode -msgSuccess "`nPVM has been setup successfully" -msgError "`nFailed to setup PVM" -exitCode $exitCode
        }
    }}
    "current" = [PSCustomObject]@{ description = "pvm current / Display active version."; action = { 
        $version = Get-Current-PHP-Version
        if (-not $version) {
            Write-Host "`nSomething went wrong, Check your environment variables !"
            exit 0
        }
        Write-Host "`nRunning version: PHP $version"
    }}
    "list" = [PSCustomObject]@{ description = "pvm list [available [-f]] / Type 'available' to list installable items. Add '-f' to force reload from source."; action = {
        if ($arguments -contains "available") {
            Get-Available-PHP-Versions -getFromSource ($arguments -contains '-f' -or $arguments -contains '--force')
        } else {
            Display-Installed-PHP-Versions
        }
    }}
    "install" = [PSCustomObject]@{ description = "pvm install <version> [--xdebug] / The version must be a specific version. '--xdebug' to include xdebug."; action = {
        $version = $arguments[0]        
        if (-not $version) {
            Write-Host "`nPlease provide a PHP version to install"
            exit 1
        }

        $dirArg = $arguments | Where-Object { $_ -like '--dir=*' }
        
        if ($dirArg) {
            $dirValue = $dirArg -replace '^--dir=', ''
        }

        Install-PHP -version $version -includeXDebug ($arguments -contains '--xdebug') -customDir $dirValue
    }}
    "uninstall" = [PSCustomObject]@{ description = "pvm uninstall <version> / The version must be a specific version."; action = {
        $version = $arguments[0]

        if (-not $version) {
            Write-Host "`nPlease provide a PHP version to uninstall"
            exit 1
        }
        if (-not (Is-Admin)) {
            # Relaunch as administrator with hidden window
            $arguments = "-ExecutionPolicy Bypass -File `"$PSCommandPath`" uninstall `"$version`""
            $process = Start-Process powershell -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru
            $process.WaitForExit()
            $exitCode = $process.ExitCode
        } else {
            $exitCode = Uninstall-PHP -version $version
        }

        Display-Msg-By-ExitCode -msgSuccess "`nPHP $version has been uninstalled successfully" -msgError "`nFailed to uninstall PHP $version" -exitCode $exitCode
    }}
    "use" = [PSCustomObject]@{ description = "pvm use [version] / Switch to use the specified version."; action = {
        $version = $arguments[0]

        if (-not $version) {
            Write-Host "`nPlease provide a PHP version to use"
            exit 1
        }
        if (-not (Is-Admin)) {
            # Relaunch as administrator with hidden window
            $arguments = "-ExecutionPolicy Bypass -File `"$PSCommandPath`" use `"$version`""
            $process = Start-Process powershell -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru
            $process.WaitForExit()
            $exitCode = $process.ExitCode
        } else {
            $exitCode = Update-PHP-Version -variableName $USER_ENV["PHP_CURRENT_ENV_NAME"] -variableValue $version
        }

        Display-Msg-By-ExitCode -msgSuccess "`nNow using PHP $version" -msgError "`nSomething went wrong, Check your environment variables !" -exitCode $exitCode
    }}
    "set" = [PSCustomObject]@{ description = "pvm set [name] [value] / Set a new evironment variable for a PHP version."; action = {
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
            $arguments = "-ExecutionPolicy Bypass -File `"$PSCommandPath`" set `"$varName`" `"$varValue`""
            $process = Start-Process powershell -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru
            $process.WaitForExit()
            $exitCode = $process.ExitCode
        } else {
            $exitCode = Set-PHP-Env -name $varName -value $varValue
        }

        Display-Msg-By-ExitCode -msgSuccess "`nEnvironment variable '$varName' set to '$varValue' at the system level." -msgError "`nSomething went wrong, Check your environment variables !" -exitCode $exitCode
    }}
}

if (-not $actions.Contains($operation)) {
    $version = Get-Current-PHP-Version
    Write-Host "`nRunning version : $version"
    Write-Host "`nUsage:`n"
    $maxLineLength = 60
    $actions.GetEnumerator() | ForEach-Object {
        $parts = $_.Value.description -split '\s*/\s*'
        $item = [PSCustomObject]@{
            Left  = $parts[0]
            Right = $parts[1]
        }
        $dotsCount = $maxLineLength - $item.Left.Length
        if ($dotsCount -lt 0) { $dotsCount = 0 }
        $dots = '.' * $dotsCount
        Write-Host "$($item.Left) $dots $($item.Right)"
    }
    exit 1
}

try {
    $actions[$operation].action.Invoke()
} catch {
    Write-Host "`nOperation canceled or failed to elevate privileges." -ForegroundColor DarkYellow
    exit 1
}