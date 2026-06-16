
function List-Cache-Files {
    try {
        if (Is-Directory-Not-Exists -path $CACHE_PATH) {
            Write-Host -Object "`nNo cache directory found." -ForegroundColor DarkYellow
            return -1
        }

        $cacheFiles = Get-ChildItem -Path $CACHE_PATH -Filter '*.json' -ErrorAction SilentlyContinue

        if ($cacheFiles.Count -eq 0) {
            Write-Host -Object "`nNo cache files found." -ForegroundColor DarkYellow
            return -1
        }

        Write-Host -Object "`nAvailable Cache Files:" -ForegroundColor Cyan
        Write-Host -Object '-------------------'

        foreach ($cacheFile in $cacheFiles) {
            Write-Host -Object "  $($cacheFile.BaseName)"
        }

        return 0
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to list cache files"; exception = $_ }
        Write-Host -Object "`nFailed to list cache files." -ForegroundColor DarkYellow
        return -1
    }
}

function Show-Cache-Data {
    param ($cacheName)

    try {
        $cachePath = Get-Cache-FilePath -fileName $cacheName
        if (Is-File-Not-Exists -path $cachePath) {
            Write-Host -Object "`nCache file '$cacheName' not found." -ForegroundColor DarkYellow
            Write-Host -Object "  Use 'pvm cache list' to see available cache files." -ForegroundColor Gray
            return -1
        }

        $cacheData = Get-Data-From-Cache -cacheFileName $cacheName

        if ($null -eq $cacheData -or $cacheData.Count -eq 0) {
            Write-Host -Object "`nNo data found in cache file '$cacheName'." -ForegroundColor DarkYellow
            return -1
        }

        Write-Host -Object "`nCache Data for '$cacheName':"
        Write-Host -Object '--------------------------------'

        Write-Host -Object ($cacheData | ConvertTo-Json)

        return 0
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to show cache data"; exception = $_ }
        Write-Host -Object "`nFailed to show cache data." -ForegroundColor DarkYellow
        return -1
    }
}

function Delete-Cache-File {
    param ($cacheName)

    try {
        $cachePath = Get-Cache-FilePath -fileName $cacheName
        if (Is-File-Not-Exists -path $cachePath) {
            Write-Host -Object "`nCache file '$cacheName' not found." -ForegroundColor DarkYellow
            Write-Host -Object "  Use 'pvm cache list' to see available cache files." -ForegroundColor Gray
            return -1
        }

        $response = Read-Host -Prompt "`nAre you sure you want to delete cache file '$cacheName'? (y/n)"
        $response = $response.Trim()
        if ($response -ne 'y' -and $response -ne 'Y') {
            Write-Host -Object "`nDeletion cancelled." -ForegroundColor Gray
            return -1
        }

        Remove-Item -Path $cachePath -Force
        Write-Host -Object "`nCache file '$cacheName' deleted successfully." -ForegroundColor DarkGreen

        return 0
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to delete cache file '$cacheName'"; exception = $_ }
        Write-Host -Object "`nFailed to delete cache file: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return -1
    }
}

function Clear-Cache-Files {
    try {
        $cacheFiles = Get-ChildItem -Path $CACHE_PATH -Filter '*.json' -ErrorAction SilentlyContinue

        if ($cacheFiles.Count -eq 0) {
            Write-Host -Object "`nNo cache files found." -ForegroundColor DarkYellow
            return -1
        }

        $response = Read-Host -Prompt "`nAre you sure you want to delete all cache files? (y/n)"
        $response = $response.Trim()
        if ($response -ne 'y' -and $response -ne 'Y') {
            Write-Host -Object "`nDeletion cancelled." -ForegroundColor Gray
            return -1
        }

        foreach ($cacheFile in $cacheFiles) {
            Remove-Item -Path $cacheFile.FullName -Force
        }

        Write-Host -Object "`nAll cache files deleted successfully." -ForegroundColor DarkGreen

        return 0
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to clear cache files"; exception = $_ }
        Write-Host -Object "`nFailed to clear cache files." -ForegroundColor DarkYellow
        return -1
    }
}