
function Get-LastUpdateCheckTimestamp {
    try {
        $timestampFile = "$($PVMConfig.paths.directories.cache)\last_update_check.txt"
        if (Test-FileExists -path $timestampFile) {
            return [DateTime](Get-ContentWrapper -path $timestampFile)
        }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get last update check timestamp"; exception = $_ }
        return $null
    }
}

function Set-LastUpdateCheckTimestamp {
    try {
        $timestampFile = "$($PVMConfig.paths.directories.cache)\last_update_check.txt"
        $created = New-Directory -path $PVMConfig.paths.directories.cache
        if ($created -ne 0) {
            Show-Error -message "`nFailed to create cache directory."
            return -1
        }
        Set-ContentWrapper -path $timestampFile -value (Get-Date)
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to set last update check timestamp"; exception = $_ }
        return -1
    }
}

function Test-ShouldCheckForUpdates {
    if (-not $PVMConfig.env.ENABLE_UPDATE_CHECK) {
        return $false
    }

    $lastCheck = Get-LastUpdateCheckTimestamp
    if (-not $lastCheck) {
        return $true
    }

    $hoursSinceCheck = ((Get-Date) - $lastCheck).TotalHours
    return ($hoursSinceCheck -ge $PVMConfig.env.UPDATE_CHECK_INTERVAL_HOURS)
}

function Test-CheckForUpdatesQuietly {
    if (-not (Test-ShouldCheckForUpdates)) {
        return 0
    }

    try {
        $code = Update-PVM -checkOnly -quiet
        $null = Set-LastUpdateCheckTimestamp

        if ($code -eq 1) {
            Show-Info -message "`nUpdate available: Run 'pvm update' to update."
        }

        return $code
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to check for updates"; exception = $_ }
        return -1
    }
}
