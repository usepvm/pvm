
function Get-LastUpdateCheckTimestamp {
    try {
        $timestampFile = $Global:PVMConfig.paths.files.lastUpdateCheck
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
        $timestampFile = $Global:PVMConfig.paths.files.lastUpdateCheck
        $created = New-Directory -path $Global:PVMConfig.paths.directories.state
        if ($created -ne 0) {
            Show-Error -message "`nFailed to create state directory."
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
    if (-not $Global:PVMConfig.env.ENABLE_UPDATE_CHECK) {
        return $false
    }

    $lastCheck = Get-LastUpdateCheckTimestamp
    if (-not $lastCheck) {
        return $true
    }

    $hoursSinceCheck = ((Get-Date) - $lastCheck).TotalHours
    return ($hoursSinceCheck -ge $Global:PVMConfig.env.UPDATE_CHECK_INTERVAL_HOURS)
}

function Test-CheckForUpdatesQuietly {
    if (-not (Test-ShouldCheckForUpdates)) {
        return 0
    }

    try {
        $result = Update-PVM -checkOnly -quiet
        $null = Set-LastUpdateCheckTimestamp

        if ($result.code -eq 1) {
            Show-Info -message "`nUpdate available: Run 'pvm update' to update."
        }

        return $result.code
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to check for updates"; exception = $_ }
        return -1
    }
}
