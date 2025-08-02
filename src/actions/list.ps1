

function Cache-Fetched-PHP-Versions {
    param ($listPhpVersions)

    try {
        $jsonString = $listPhpVersions | ConvertTo-Json -Depth 3
        $versionsDataPath = "$DATA_PATH\available_versions.json"
        Make-Directory -path (Split-Path $versionsDataPath)
        Set-Content -Path $versionsDataPath -Value $jsonString
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Cache-Fetched-PHP-Versions: Failed to cache fetched PHP versions" -data $_.Exception.Message
    }
}

function Get-From-Source {

    try {
        $urls = Get-Source-Urls
        $fetchedVersions = @()
        foreach ($key in $urls.Keys) {
            $html = Invoke-WebRequest -Uri $urls[$key]
            $links = $html.Links

            # Filter the links to find versions that match the given version
            $filteredLinks = $links | Where-Object { 
                $_.href -match "php-\d+\.\d+\.\d+(?:-\d+)?-Win32.*\.zip$" -and
                $_.href -notmatch "php-debug" -and
                $_.href -notmatch "php-devel" -and
                $_.href -notmatch "nts"
            }
            # Return the filtered links (PHP version names)
            $fetchedVersions = $fetchedVersions + ($filteredLinks | ForEach-Object { $_.href })
        }
        
        $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') { 'x64' } else { 'x86' }
        $fetchedVersions = $fetchedVersions | Where-Object { $_ -match "$arch" }
        $fetchedVersions = $fetchedVersions | Select-Object -Last 10
        
        $fetchedVersionsGrouped = @{
            'Archives' = $fetchedVersions | Where-Object { $_ -match "archives" }
            'Releases' = $fetchedVersions | Where-Object { $_ -notmatch "archives" }
        }
        
        if ($fetchedVersionsGrouped['Archives'].Count -eq 0 -and $fetchedVersionsGrouped['Releases'].Count -eq 0) {
            Write-Host "`nNo PHP versions found in the source."
            return @{}
        }
        
        Cache-Fetched-PHP-Versions $fetchedVersionsGrouped
        
        return $fetchedVersionsGrouped
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-From-Source: Failed to fetch PHP versions from source" -data $_.Exception.Message
        return @{}
    }
}

function Get-From-Cache {
    
    try {
        $list = @{}
        $jsonData = Get-Content "$DATA_PATH\available_versions.json" | ConvertFrom-Json
        $jsonData.PSObject.Properties.GetEnumerator() | ForEach-Object {
            $key = $_.Name
            $value = $_.Value
            
            # Add the key-value pair to the hashtable
            $list[$key] = $value
        }
        return $list
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-From-Cache: Failed to retrieve cached PHP versions" -data $_.Exception.Message
        return @{}
    }
}

function Get-Available-PHP-Versions {
    param ($getFromSource = $null)
    
    try {
        $fetchedVersionsGrouped = @{}

        if (-not $getFromSource) {
            Write-Host "`nReading from the cache"
            $fetchedVersionsGrouped = Get-From-Cache
        }
        
        if ($fetchedVersionsGrouped.Count -eq 0) {
            Write-Host "`nCache empty!, Reading from the internet..."
            $fetchedVersionsGrouped = Get-From-Source
        }

        if ($fetchedVersionsGrouped.Count -eq 0) {
            Write-Host "`nNo PHP versions found in the source. Please check your internet connection or the source URLs."
            return 1
        }
        
        Write-Host "`nAvailable Versions"
        Write-Host "--------------"

        $fetchedVersionsGrouped.GetEnumerator() | ForEach-Object {
            $key = $_.Key
            $fetchedVersionsGroupe = $_.Value
            Write-Host "`n$key`n"
            $fetchedVersionsGroupe | ForEach-Object {
                $versionItem = $_ -replace '/downloads/releases/archives/|/downloads/releases/|php-|-Win.*|.zip', ''
                Write-Host "  $versionItem"
            }
        }
        
        $msg = "`nThis is a partial list. For a complete list, visit"
        $msg += "`nReleases : https://windows.php.net/downloads/releases"
        $msg += "`nArchives : https://windows.php.net/downloads/releases/archives"
        Write-Host $msg
        return 0
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-Available-PHP-Versions: Failed to get available PHP versions" -data $_.Exception.Message
        return 1
    }
}

function Display-Installed-PHP-Versions {

    try {
        $currentVersion = (Get-Current-PHP-Version).version
        $installedPhp = Get-Installed-PHP-Versions
        
        if ($installedPhp.Count -eq 0) {
            Write-Host "`nNo PHP versions found"
            return 1
        }

        Write-Host "`nInstalled Versions"
        Write-Host "--------------"
        $duplicates = @()
        $installedPhp | ForEach-Object {
            $versionNumber = $_ -replace "php",""
            if ($duplicates -notcontains $versionNumber) {
                $duplicates += $versionNumber
                $isCurrent = ""
                if ($currentVersion -eq $versionNumber) {
                    $isCurrent = "(Current)"
                }
                Write-Host "  $versionNumber $isCurrent"
            }
        }
        return 0
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Display-Installed-PHP-Versions: Failed to display installed PHP versions" -data $_.Exception.Message
        return 1
    }
    
}