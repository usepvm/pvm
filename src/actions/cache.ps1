
function Get-CacheFiles {
    try {
        if (Test-DirectoryNotExists -path $Global:PVMConfig.paths.directories.cache) {
            return $null
        }

        $files = Get-ChildItemWrapper -path $Global:PVMConfig.paths.directories.cache -filter '*.json'

        return $files
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get cache files"; exception = $_ }
        return $null
    }
}

function Show-CacheFiles {
    try {
        if (Test-DirectoryNotExists -path $Global:PVMConfig.paths.directories.cache) {
            Show-LabelledError -message "No cache directory found."
            return -1
        }

        $cacheFiles = Get-CacheFiles

        if ($cacheFiles.Count -eq 0) {
            Show-LabelledError -message "No cache files found."
            return -1
        }

        Write-Cyan -message "`nAvailable Cache Files:" -underlined

        foreach ($cacheFile in $cacheFiles) {
            Show-Message -message "  $($cacheFile.BaseName)"
        }

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to list cache files"; exception = $_ }
        Show-Error -message "`nFailed to list cache files."
        return -1
    }
}

function Show-CachedData {
    param ($cacheName)

    try {
        $cachePath = Get-CacheFilePath -fileName $cacheName
        if (Test-FileNotExists -path $cachePath) {
            $msg = "Cache file '$cacheName' not found."
            $msg += "`nUse 'pvm cache list' to see available cache files."
            Show-LabelledError -message $msg
            return -1
        }

        $cacheData = Get-DataFromCache -cacheFileName $cacheName

        if ($null -eq $cacheData -or $cacheData.Count -eq 0) {
            Show-LabelledError -message "No data found in cache file '$cacheName'."
            return -1
        }

        Write-Cyan -message "`nCache Data for '$cacheName':" -underlined

        Show-Message -message ($cacheData | ConvertTo-Json)

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to show cache data"; exception = $_ }
        Show-LabelledError -message "Failed to show cache data."
        return -1
    }
}

function Remove-CacheFile {
    param ($cacheName, $skipConfirmation = $false)

    try {
        $cachePath = Get-CacheFilePath -fileName $cacheName
        if (Test-FileNotExists -path $cachePath) {
            $msg = "Cache file '$cacheName' not found."
            $msg += "`nUse 'pvm cache list' to see available cache files."
            Show-LabelledError -message $msg
            return -1
        }

        if (-not $skipConfirmation) {
            $response = Read-HostWrapper -prompt "`nAre you sure you want to delete cache file '$cacheName'? (y/n)"
            if (Test-NoResponse -response $response) {
                Write-Gray -message "`nDeletion cancelled."
                return -1
            }
        }

        $code = Remove-ItemWrapper -path $cachePath
        if ($code -ne 0) {
            Show-LabelledError -message "Failed to remove '$cacheName' file!"
            return -1
        }

        Show-LabelledSuccess -message "Cache file '$cacheName' deleted successfully."
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to delete cache file '$cacheName'"; exception = $_ }
        Show-LabelledError -message "Failed to delete cache file: $($_.Exception.Message)"
        return -1
    }
}

function Clear-CacheFiles {
    param ($skipConfirmation = $false)

    try {
        $cacheFiles = Get-CacheFiles

        if ($cacheFiles.Count -eq 0) {
            Show-LabelledError -message "No cache files found."
            return -1
        }

        if (-not $skipConfirmation) {
            $response = Read-HostWrapper -prompt "`nAre you sure you want to delete all cache files? (y/n)"
            if (Test-NoResponse -response $response) {
                Write-Gray -message "`nDeletion cancelled."
                return -1
            }
        }

        $code = Remove-ItemWrapper -path "$($Global:PVMConfig.paths.directories.cache)\*"
        if ($code -ne 0) {
            Show-LabelledError -message "Failed to remove all cache files!"
            return -1
        }

        Show-LabelledSuccess -message "All cache files deleted successfully."
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to clear cache files"; exception = $_ }
        Show-LabelledError -message "Failed to clear cache files."
        return -1
    }
}
