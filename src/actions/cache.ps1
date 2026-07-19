
function Get-Cache-Files {
    try {
        if (Is-Directory-Not-Exists -path $PVMConfig.paths.cache) {
            return $null
        }

        $files = Get-ChildItem -Path $PVMConfig.paths.cache -Filter '*.json' -ErrorAction SilentlyContinue

        return $files
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get cache files"; exception = $_ }
        return $null
    }
}

function List-Cache-Files {
    try {
        if (Is-Directory-Not-Exists -path $PVMConfig.paths.cache) {
            Print-Error -message "`nNo cache directory found."
            return -1
        }

        $cacheFiles = Get-Cache-Files

        if ($cacheFiles.Count -eq 0) {
            Print-Error -message "`nNo cache files found."
            return -1
        }

        Print-Info -message "`nAvailable Cache Files:"
        Write-Gray -message '-------------------'

        foreach ($cacheFile in $cacheFiles) {
            Print-Message -message "  $($cacheFile.BaseName)"
        }

        return 0
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to list cache files"; exception = $_ }
        Print-Error -message "`nFailed to list cache files."
        return -1
    }
}

function Show-Cache-Data {
    param ($cacheName)

    try {
        $cachePath = Get-Cache-FilePath -fileName $cacheName
        if (Is-File-Not-Exists -path $cachePath) {
            Print-Error -message "`nCache file '$cacheName' not found."
            Print-Message -message "  Use 'pvm cache list' to see available cache files."
            return -1
        }

        $cacheData = Get-Data-From-Cache -cacheFileName $cacheName

        if ($null -eq $cacheData -or $cacheData.Count -eq 0) {
            Print-Error -message "`nNo data found in cache file '$cacheName'."
            return -1
        }

        Print-Info -message "`nCache Data for '$cacheName':"
        Write-Gray -message '--------------------------------'

        Print-Message -message ($cacheData | ConvertTo-Json)

        return 0
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to show cache data"; exception = $_ }
        Print-Error -message "`nFailed to show cache data."
        return -1
    }
}

function Delete-Cache-File {
    param ($cacheName, $skipConfirmation = $false)

    try {
        $cachePath = Get-Cache-FilePath -fileName $cacheName
        if (Is-File-Not-Exists -path $cachePath) {
            Print-Error -message "`nCache file '$cacheName' not found."
            Print-Message -message "  Use 'pvm cache list' to see available cache files."
            return -1
        }

        if (-not $skipConfirmation) {
            $response = Read-Host -Prompt "`nAre you sure you want to delete cache file '$cacheName'? (y/n)"
            $response = $response.Trim()
            if ($response -ne 'y' -and $response -ne 'Y') {
                Write-Gray -message "`nDeletion cancelled."
                return -1
            }
        }

        Remove-Item -Path $cachePath -Force
        Print-Success -message "`nCache file '$cacheName' deleted successfully."

        return 0
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to delete cache file '$cacheName'"; exception = $_ }
        Print-Error -message "`nFailed to delete cache file: $($_.Exception.Message)"
        return -1
    }
}

function Clear-Cache-Files {
    param ($skipConfirmation = $false)

    try {
        $cacheFiles = Get-Cache-Files

        if ($cacheFiles.Count -eq 0) {
            Print-Error -message "`nNo cache files found."
            return -1
        }

        if (-not $skipConfirmation) {
            $response = Read-Host -Prompt "`nAre you sure you want to delete all cache files? (y/n)"
            $response = $response.Trim()
            if ($response -ne 'y' -and $response -ne 'Y') {
                Write-Gray -message "`nDeletion cancelled."
                return -1
            }
        }

        foreach ($cacheFile in $cacheFiles) {
            Remove-Item -Path $cacheFile.FullName -Force
        }

        Print-Success -message "`nAll cache files deleted successfully."

        return 0
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to clear cache files"; exception = $_ }
        Print-Error -message "`nFailed to clear cache files."
        return -1
    }
}
