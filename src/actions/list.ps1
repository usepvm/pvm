
function Get-From-Source {
    param ($arch = $null)

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
        
        if ($null -ne $arch) {
            $fetchedVersions = $fetchedVersions | Where-Object { $_ -match $arch }
        }
        
        $fetchedVersionsGrouped = [ordered]@{
            'Archives' = $fetchedVersions | Where-Object { $_ -match "archives" }
            'Releases' = $fetchedVersions | Where-Object { $_ -notmatch "archives" }
        }
        
        if ($fetchedVersionsGrouped.Count -eq 0 -or 
            ($fetchedVersionsGrouped['Archives'].Count -eq 0 -and $fetchedVersionsGrouped['Releases'].Count -eq 0)) {
            Write-Host "`nNo PHP versions found in the source."
            return @{}
        }
        
        $cached = Cache-Data -cacheFileName "available_php_versions" -data $fetchedVersionsGrouped -depth 3
        
        return $fetchedVersionsGrouped
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to fetch PHP versions from source"
            exception = $_
        }
        return @{}
    }
}

function Get-PHP-List-To-Install {
    param ($arch = $null)
    try {
        $fetchedVersionsGrouped = @{}
        $useCache = Can-Use-Cache -cacheFileName 'available_php_versions'
        
        if ($useCache) {
            $fetchedVersionsGrouped = Get-Data-From-Cache -cacheFileName "available_php_versions"
            if (-not $fetchedVersionsGrouped -or $fetchedVersionsGrouped.Count -eq 0) {
                $fetchedVersionsGrouped = Get-From-Source -arch $arch
            }
        } else {
            $fetchedVersionsGrouped = Get-From-Source -arch $arch
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
    param($term = $null, $arch = $null)
    
    try {
        Write-Host "`nLoading available PHP versions..."

        $fetchedVersionsGrouped = Get-PHP-List-To-Install -arch $arch

        if ($fetchedVersionsGrouped.Count -eq 0) {
            Write-Host "`nNo PHP versions found in the source. Please check your internet connection or the source URLs."
            return -1
        }
        
        $fetchedVersionsGroupedPartialList = @{}
        $fetchedVersionsGrouped.GetEnumerator() | ForEach-Object {
            $searchResult = $_.Value
            if ($term) {
                $searchResult = $searchResult | Where-Object {
                    $_ -like "*php-$term*"
                }
            }
            if ($searchResult.Count -ne 0) {
                $fetchedVersionsGroupedPartialList[$_.Key] = $searchResult | Select-Object -Last $LATEST_VERSION_COUNT
            }
        }
        
        if ($fetchedVersionsGroupedPartialList.Count -eq 0) {
            Write-Host "`nNo PHP versions found matching '$term'"
            return -1
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
                $fileName = $_ -split "/"
                $fileName = $fileName[$fileName.Count - 1]
                $arch = ($fileName -replace '.*\b(x64|x86)\b.*', '$1')
                
                Write-Host "  $versionItem $arch"
            }
        }
        
        $msg = "`nThis is a partial list. For a complete list, visit:"
        $msg += "`n Releases : $PHP_WIN_RELEASES_URL"
        $msg += "`n Archives : $PHP_WIN_ARCHIVES_URL"
        Write-Host $msg
        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to get available PHP versions"
            exception = $_
        }
        return -1
    }
}

function Display-Installed-PHP-Versions {
    param ($term)

    try {
        $currentVersion = Get-Current-PHP-Version
        if ($currentVersion -and $currentVersion.version) {
            $currentVersion = $currentVersion.version
        }
        $installedPhp = Get-Installed-PHP-Versions
        
        if ($installedPhp.Count -eq 0) {
            Write-Host "`nNo PHP versions found"
            return -1
        }
        
        if ($term) {
            $installedPhp = $installedPhp | Where-Object { $_ -like "$term*" }
            if ($installedPhp.Count -eq 0) {
                Write-Host "`nNo PHP versions found matching '$term'"
                return -1
            }
        }

        Write-Host "`nInstalled Versions"
        Write-Host "------------------"
        $duplicates = @()
        $installedPhp | ForEach-Object {
            $versionNumber = $_.name
            $arch = $_.arch
            if ($duplicates -notcontains $versionNumber) {
                $duplicates += "$($versionNumber)_$($arch)"
                $isCurrent = ""
                if ($arch) {
                    $versionNumber += " " + $arch
                }
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
        return -1
    }
    
}


function Get-PHP-Versions-List {
    param($available = $false, $term = $null, $arch = $null)
    
    if ($available) {
        $result = Get-Available-PHP-Versions -term $term -arch $arch
    } else {
        $result = Display-Installed-PHP-Versions -term $term
    }
    
    return $result
}