
function Get-PHPStatus {
    param ($phpPath)

    # Build zendExtensions list from ini status
    $status = @(
        @{ Name = 'opcache'; Version = $null; Copyright = $null; Enabled = $false }
        @{ Name = 'xdebug'; Version = $null; Copyright = $null; Enabled = $false }
    )

    try {
        $phpIniPath = "$phpPath\php.ini"
        if (Test-FileNotExists -path $phpIniPath) {
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
        $dllExtensions = Get-ZendExtensionsInfo -phpPath $phpPath

        # Update with DLL version info if available
        foreach ($dllExt in $dllExtensions) {
            $extToUpdate = $status | Where-Object { $_.Name -eq $dllExt.Name }
            if ($extToUpdate) {
                $extToUpdate.Version = $dllExt.Version
                $extToUpdate.Copyright = $dllExt.Copyright
            }
        }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to retrieve PHP status"; exception = $_ }
        Show-Error -message "An error occurred while checking PHP status: $_"
    }

    return $status
}

function Get-CurrentPHPVersion {
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
        if (Test-DirectoryNotExists -path $currentPhpVersionPath) {
            return $emptyResult
        }
        $phpInfo = Get-PHPInstallInfo -path $currentPhpVersionPath

        return @{
            version   = $phpInfo.Version
            arch      = $phpInfo.Arch
            buildType = $phpInfo.BuildType
            path      = $phpInfo.InstallPath
            status    = Get-PHPStatus -phpPath $currentPhpVersionPath
        }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to retrieve current PHP version"; exception = $_ }
        return $emptyResult
    }
}
