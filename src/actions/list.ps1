

function Cache-Fetched-PHP-Versions {
    param ($listPhpVersions)

    try {
        if (-not $listPhpVersions -or $listPhpVersions.Count -eq 0) {
            return -1
        }
        
        return (Cache-Data -cacheFileName "available_php_versions" -data $listPhpVersions -depth 3)
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to cache fetched PHP versions"
            exception = $_
        }
        return -1
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
        
        $fetchedVersionsGrouped = @{
            'Archives' = $fetchedVersions | Where-Object { $_ -match "archives" }
            'Releases' = $fetchedVersions | Where-Object { $_ -notmatch "archives" }
        }
        
        if ($fetchedVersionsGrouped['Archives'].Count -eq 0 -and $fetchedVersionsGrouped['Releases'].Count -eq 0) {
            Write-Host "`nNo PHP versions found in the source."
            return @{}
        }
        
        $cached = Cache-Fetched-PHP-Versions $fetchedVersionsGrouped
        
        return $fetchedVersionsGrouped
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to fetch PHP versions from source"
            exception = $_
        }
        return @{}
    }
}

function Get-From-Cache {
    
    try {
        return (Get-Data-From-Cache -cacheFileName "available_php_versions")
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to retrieve cached PHP versions"
            exception = $_
        }
        return @{}
    }
}

function Get-PHP-List-To-Install {
    try {
        $cacheFile = "$DATA_PATH\available_php_versions.json"
        $fetchedVersionsGrouped = @{}
        $useCache = $false

        if (Test-Path $cacheFile) {
            $fileAgeHours = (New-TimeSpan -Start (Get-Item $cacheFile).LastWriteTime -End (Get-Date)).TotalHours
            $useCache = ($fileAgeHours -lt $CacheMaxHours)
        }
        
        if ($useCache) {
            Write-Host "`nReading from the cache (last updated $([math]::Round($fileAgeHours, 2)) hours ago)"
            $fetchedVersionsGrouped = Get-From-Cache
            if (-not $fetchedVersionsGrouped -or $fetchedVersionsGrouped.Count -eq 0) {
                Write-Host "`nCache is empty, reading from the source..."
                $fetchedVersionsGrouped = Get-From-Source
            }
        } else {
            if (Test-Path $cacheFile) {
                Write-Host "`nCache too old ($([math]::Round($fileAgeHours, 2)) hours), reading from the internet..."
            } else {
                Write-Host "`nCache missing, reading from the source..."
            }
            $fetchedVersionsGrouped = Get-From-Source
        }
        
        return $fetchedVersionsGrouped
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to get fetch PHP versions"
            exception = $_
        }
        return @{}
    }
}

function Get-Available-PHP-Versions {
    
    try {
        $fetchedVersionsGrouped = Get-PHP-List-To-Install

        if ($fetchedVersionsGrouped.Count -eq 0) {
            Write-Host "`nNo PHP versions found in the source. Please check your internet connection or the source URLs."
            return 1
        }
        
        $fetchedVersionsGroupedPartialList = @{}
        $fetchedVersionsGrouped.GetEnumerator() | ForEach-Object {
            $fetchedVersionsGroupedPartialList[$_.Key] = $_.Value | Select-Object -Last $LatestVersionCount
        }
        
        Write-Host "`nAvailable Versions"
        Write-Host "------------------"

        $fetchedVersionsGroupedPartialList.GetEnumerator() | ForEach-Object {
            $key = $_.Key
            $fetchedVersionsGroupe = $_.Value
            if ($fetchedVersionsGroupe.Length -eq 0) {
                return
            }
            Write-Host "`n$key`n"
            $fetchedVersionsGroupe | ForEach-Object {
                $versionItem = $_ -replace '/downloads/releases/archives/|/downloads/releases/|php-|-Win.*|.zip', ''
                Write-Host "  $versionItem"
            }
        }
        
        $msg = "`nThis is a partial list. For a complete list, visit:"
        $msg += "`n Releases : https://windows.php.net/downloads/releases"
        $msg += "`n Archives : https://windows.php.net/downloads/releases/archives"
        Write-Host $msg
        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to get available PHP versions"
            exception = $_
        }
        return 1
    }
}

function Display-Installed-PHP-Versions {

    try {
        $currentVersion = Get-Current-PHP-Version
        if ($currentVersion -and $currentVersion.version) {
            $currentVersion = $currentVersion.version
        }
        $installedPhp = Get-Installed-PHP-Versions
        
        if ($installedPhp.Count -eq 0) {
            Write-Host "`nNo PHP versions found"
            return 1
        }

        Write-Host "`nInstalled Versions"
        Write-Host "------------------"
        $duplicates = @()
        $installedPhp | ForEach-Object {
            $versionNumber = $_
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
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to display installed PHP versions"
            exception = $_
        }
        return 1
    }
    
}