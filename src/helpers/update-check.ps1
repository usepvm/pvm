
function Get-Last-Update-Check-Timestamp {
    try {
        $timestampFile = "$($PVMConfig.paths.cache)\last_update_check.txt"
        if (Test-File-Exists -path $timestampFile) {
            return [DateTime](Get-Content -Path $timestampFile)
        }
    } catch {
        return $null
    }
}

function Set-Last-Update-Check-Timestamp {
    try {
        $timestampFile = "$($PVMConfig.paths.cache)\last_update_check.txt"
        $null = New-Directory -path $PVMConfig.paths.cache
        Set-Content -Path $timestampFile -Value (Get-Date)
        return 0
    } catch {
        return -1
    }
}

function Test-Should-Check-For-Updates {
    if (-not $PVMConfig.env.ENABLE_UPDATE_CHECK) {
        return $false
    }

    $lastCheck = Get-Last-Update-Check-Timestamp
    if (-not $lastCheck) {
        return $true
    }

    $hoursSinceCheck = ((Get-Date) - $lastCheck).TotalHours
    return ($hoursSinceCheck -ge $PVMConfig.env.UPDATE_CHECK_INTERVAL_HOURS)
}

function Test-Check-For-Updates-Quietly {
    if (-not (Test-Should-Check-For-Updates)) {
        return 0
    }

    try {
        $result = Update-PVM -checkOnly $true -quiet $true
        $null = Set-Last-Update-Check-Timestamp

        if ($result.code -eq 0 -and $result.message -like '*Update available*') {
            Print-Error -Message "`n$($result.message) Run 'pvm update' to update."
        }

        return $result.code
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to check for updates"; exception = $_ }
        return -1
    }
}
