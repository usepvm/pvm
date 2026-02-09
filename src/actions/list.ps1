
function Get-From-Source {

    try {
        $urls = Get-Source-Urls
        $fetchedVersions = @()
        foreach ($key in $urls.Keys) {
            $html = Invoke-WebRequest -Uri $urls[$key]
            $links = $html.Links

            # Filter the links to find versions that match the given version
            $filteredLinks = @()
            $links | ForEach-Object {
                if ($_.href -match "php-\d+\.\d+\.\d+(?:-\d+)?-(?:nts-)?Win32.*\.zip$" -and
                    $_.href -notmatch "php-debug" -and
                    $_.href -notmatch "php-devel" # -and $_.href -notmatch "nts"
                ) {
                    $fileName = $_.href -split "/"
                    $fileName = $fileName[$fileName.Count - 1]
                    
                    $filteredLinks += @{
                        Version = ($_.href -replace '/downloads/releases/archives/|/downloads/releases/|php-|-nts|-Win.*|\.zip', '')
                        Arch    = ($fileName -replace '.*\b(x64|x86)\b.*', '$1')
                        BuildType = if ($fileName -match 'nts') { 'NTS' } else { 'TS' }
                        Link    = $_.href
                    }
                }
            }
            # Return the filtered links (PHP version names)
            $fetchedVersions = $fetchedVersions + $filteredLinks # ($filteredLinks | ForEach-Object { $_.href })
        }
        
        $fetchedVersionsGrouped = [ordered]@{
            'Archives' = $fetchedVersions | Where-Object { $_.Link -match "archives" }
            'Releases' = $fetchedVersions | Where-Object { $_.Link -notmatch "archives" }
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
    try {
        $fetchedVersionsGrouped = Get-OrUpdateCache -cacheFileName "available_php_versions" -compute {
            Get-From-Source
        }

        if (-not $fetchedVersionsGrouped) {
            return @{}
        }
        
        $fetchedVersionsGrouped = [pscustomobject] $fetchedVersionsGrouped
        
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

        $fetchedVersionsGrouped = Get-PHP-List-To-Install

        if ($fetchedVersionsGrouped.Count -eq 0) {
            Write-Host "`nNo PHP versions found in the source. Please check your internet connection or the source URLs."
            return -1
        }
        
        $fetchedVersionsGroupedPartialList = @{}
        $fetchedVersionsGrouped.PSObject.Properties | ForEach-Object {
            $searchResult = $_.Value
            if ($null -ne $arch) {
                $searchResult = $searchResult | Where-Object { $_.Arch -match $arch }
            }
            if ($term) {
                $searchResult = $searchResult | Where-Object { $_.Version -like "$term*" }
            }
            if ($searchResult.Count -ne 0) {
                $fetchedVersionsGroupedPartialList[$_.Name] = $searchResult | Select-Object -Last $LATEST_VERSION_COUNT
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
                $versionNumber = "$($_.Version) ".PadRight(15, '.')
                Write-Host "  $versionNumber $($_.Arch) $($_.BuildType)"
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
    param ($term = $null, $arch = $null)

    try {
        $currentVersion = Get-Current-PHP-Version
        $installedPhp = Get-Installed-PHP-Versions -arch $arch
        
        if ($installedPhp.Count -eq 0) {
            Write-Host "`nNo PHP versions found"
            return -1
        }
        
        if ($term) {
            $installedPhp = $installedPhp | Where-Object { $_.Version -like "$term*" }
            if ($installedPhp.Count -eq 0) {
                Write-Host "`nNo PHP versions found matching '$term'"
                return -1
            }
        }

        Write-Host "`nInstalled Versions"
        Write-Host "------------------"
        $duplicates = @()
        $installedPhp | ForEach-Object {
            $versionNumber = $_.Version
            $versionID = "$($_.Version)_$($_.buildType)_$($_.Arch)"
            if ($duplicates -notcontains $versionID) {
                $duplicates += $versionID
                $isCurrent = ""
                $metaData = ""
                if ($_.Arch) {
                    $metaData += $_.Arch + " "
                }
                if ($_.BuildType) {
                    $metaData += $_.BuildType
                }
                if (Is-Two-PHP-Versions-Equal -version1 $currentVersion -version2 $_) {
                    $isCurrent = "(Current)"
                }
                $versionNumber = "$versionNumber ".PadRight(15, '.')
                Write-Host " $versionNumber $metaData $isCurrent"
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
        $result = Display-Installed-PHP-Versions -term $term -arch $arch
    }
    
    return $result
}