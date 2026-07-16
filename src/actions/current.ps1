
function Get-PHP-Status {
    param ($phpPath)

    # Build zendExtensions list from ini status
    $status = @(
        @{ Name = 'opcache'; Version = $null; Copyright = $null; Enabled = $false }
        @{ Name = 'xdebug'; Version = $null; Copyright = $null; Enabled = $false }
    )

    try {
        $phpIniPath = "$phpPath\php.ini"
        if (Is-File-Not-Exists -path $phpIniPath) {
            return $status
        }

        $iniContent = Get-Content -Path $phpIniPath

        foreach ($line in $iniContent) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^(;)?\s*zend_extension\s*=.*opcache.*$') {
                $opcacheStatus = $status | Where-Object { $_.Name -eq 'opcache' }
                $opcacheStatus.Enabled = -not $trimmed.StartsWith(';')
            }

            if ($trimmed -match '^(;)?\s*zend_extension\s*=.*xdebug.*$') {
                $xdebugStatus = $status | Where-Object { $_.Name -eq 'xdebug' }
                $xdebugStatus.Enabled = -not $trimmed.StartsWith(';')
            }
        }

        # Get zend extension info from DLL files (adds version info)
        $dllExtensions = Get-Zend-Extensions-Info -phpPath $phpPath

        # Update with DLL version info if available
        foreach ($dllExt in $dllExtensions) {
            $extToUpdate = $status | Where-Object { $_.Name -eq $dllExt.Name }
            if ($extToUpdate) {
                $extToUpdate.Version = $dllExt.Version
                $extToUpdate.Copyright = $dllExt.Copyright
            }
        }
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to retrieve PHP status"; exception = $_ }
        Print-Error -message "An error occurred while checking PHP status: $_"
    }

    return $status
}

function Get-Current-PHP-Version {
    try {
        $emptyResult = @{
            version = $null; path = $null;
            status = @(
                @{ Name = 'opcache'; Version = $null; Copyright = $null; Enabled = $false }
                @{ Name = 'xdebug'; Version = $null; Copyright = $null; Enabled = $false }
            )
        }
        $currentPhpVersionPath = Get-Item -Path $PVMConfig.env.PHP_CURRENT_VERSION_PATH
        if (-not $currentPhpVersionPath) {
            return $emptyResult
        }

        $currentPhpVersionPath = $currentPhpVersionPath.Target
        if (Is-Directory-Not-Exists -path $currentPhpVersionPath) {
            return $emptyResult
        }
        $phpInfo = Get-PHPInstallInfo -path $currentPhpVersionPath

        return @{
            version   = $phpInfo.Version
            arch      = $phpInfo.Arch
            buildType = $phpInfo.BuildType
            path      = $phpInfo.InstallPath
            status    = Get-PHP-Status -phpPath $currentPhpVersionPath
        }
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to retrieve current PHP version"; exception = $_ }
        return $emptyResult
    }
}
