
function Get-From-Source {
    try {
        $urls = Get-Source-Urls
        $fetchedVersionsGrouped = @{}
        foreach ($key in $urls.Keys) {
            $html = Get-Web-Response -uri $urls[$key]
            $links = $html.Links

            # Filter the links to find versions that match the given version
            $filteredLinks = @()
            $links | ForEach-Object {
                if ($_.href -match "php-\d+\.\d+\.\d+(?:-\d+)?-(?:nts-)?Win32.*\.zip$" -and
                    $_.href -notmatch 'php-debug' -and
                    $_.href -notmatch 'php-devel' # -and $_.href -notmatch "nts"
                ) {
                    $fileName = $_.href -split '/'
                    $fileName = $fileName[$fileName.Count - 1]

                    $filteredLinks += @{
                        Version   = ($_.href -replace '/downloads/releases/archives/|/downloads/releases/|php-|-nts|-Win.*|\.zip', '')
                        Arch      = ($fileName -replace '.*\b(x64|x86)\b.*', '$1')
                        BuildType = if ($fileName -match 'nts') { 'NTS' } else { 'TS' }
                        Link      = $_.href
                    }
                }
            }
            # Return the filtered links (PHP version names)
            $fetchedVersionsGrouped[$key] = $filteredLinks
        }

        if ($fetchedVersionsGrouped.Count -eq 0 -or
            ($fetchedVersionsGrouped['Archives'].Count -eq 0 -and $fetchedVersionsGrouped['Releases'].Count -eq 0)) {
            Print-Error -message "`nNo PHP versions found in the source."
            return @{}
        }

        return $fetchedVersionsGrouped
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to fetch PHP versions from source"; exception = $_ }
        return @{}
    }
}

function Get-PHP-List-To-Install {
    try {
        $fetchedVersionsGrouped = Get-OrUpdateCache -cacheFileName 'available_php_versions' -compute {
            Get-From-Source
        }

        if (-not $fetchedVersionsGrouped) {
            return @{}
        }

        $fetchedVersionsGrouped = [pscustomobject] $fetchedVersionsGrouped

        return $fetchedVersionsGrouped
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get fetch PHP versions"; exception = $_ }
        return @{}
    }
}

function Get-Available-PHP-Versions {
    param ($term = $null, $arch = $null, $buildType = $null)

    try {
        Print-Host -message "`nLoading available PHP versions..."

        $fetchedVersionsGrouped = Get-PHP-List-To-Install

        if ($fetchedVersionsGrouped.Count -eq 0) {
            Print-Error -message "`nNo PHP versions found in the source. Please check your internet connection or the source URLs."
            return -1
        }

        $fetchedVersionsGroupedPartialList = @{}
        $fetchedVersionsGrouped.PSObject.Properties | ForEach-Object {
            $searchResult = $_.Value
            if ($null -ne $arch) {
                $searchResult = $searchResult | Where-Object { $_.Arch -eq $arch }
            }
            if ($null -ne $buildType) {
                $searchResult = $searchResult | Where-Object { $_.BuildType -eq $buildType }
            }
            if ($term) {
                $searchResult = $searchResult | Where-Object { $_.Version -like "$term*" }
            }
            if ($searchResult.Count -ne 0) {
                $fetchedVersionsGroupedPartialList[$_.Name] = $searchResult | Select-Object -Last $PVMConfig.env.DEFAULT_PARTIAL_LIST_SIZE
            }
        }

        if ($fetchedVersionsGroupedPartialList.Count -eq 0) {
            Print-Error -message "`nNo PHP versions found matching '$term'"
            return -1
        }

        Print-Info -message "`nAvailable Versions"
        Write-Gray -message '------------------'

        $fetchedVersionsGroupedPartialList.GetEnumerator() |
            Sort-Object Key |
            ForEach-Object {
                $key = $_.Key
                $fetchedVersionsGroupe = $_.Value
                if ($fetchedVersionsGroupe.Length -eq 0) {
                    return
                }
                Print-Host -message "`n$key`n"
                $maxNameLength = ($fetchedVersionsGroupe.Version | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
                $fetchedVersionsGroupe | ForEach-Object {
                    $versionNumber = "$($_.Version) ".PadRight($maxNameLength, '.')
                    Print-Host -message "  $versionNumber $($_.Arch) $($_.BuildType)"
                }
            }

        $msg = "`nThis is a partial list. For a complete list, visit:"
        $msg += "`n Releases : $($PVMConfig.links.phpWinReleases)"
        $msg += "`n Archives : $($PVMConfig.links.phpWinArchives)"
        Print-Host -message $msg
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get available PHP versions"; exception = $_ }
        return -1
    }
}

function Show-Installed-PHP-Versions {
    param ($term = $null, $arch = $null, $buildType = $null)

    try {
        $currentVersion = Get-Current-PHP-Version
        $installedPhp = Get-Installed-PHP-Versions -arch $arch -buildType $buildType

        if ($installedPhp.Count -eq 0) {
            Print-Error -message "`nNo PHP versions found"
            return -1
        }

        if ($term) {
            $installedPhp = $installedPhp | Where-Object { $_.Version -like "$term*" }
            if ($installedPhp.Count -eq 0) {
                Print-Error -message "`nNo PHP versions found matching '$term'"
                return -1
            }
        }

        Print-Info -message "`nInstalled Versions"
        Write-Gray -message '------------------'
        $duplicates = @()
        $maxNameLength = ($installedPhp.Version | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
        $installedPhp | ForEach-Object {
            $versionNumber = $_.Version
            $versionID = "$($_.Version)_$($_.buildType)_$($_.Arch)"
            if ($duplicates -notcontains $versionID) {
                $duplicates += $versionID
                $isCurrent = ''
                $metaData = ''
                if ($_.Arch) {
                    $metaData += $_.Arch + ' '
                }
                if ($_.BuildType) {
                    $metaData += $_.BuildType
                }
                if (Test-Two-PHP-Versions-Equal -version1 $currentVersion -version2 $_) {
                    $isCurrent = '(Current)'
                }
                $versionNumber = "$versionNumber ".PadRight($maxNameLength, '.')
                Print-Host -message " $versionNumber $metaData $isCurrent"
            }
        }
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to display installed PHP versions"; exception = $_ }
        return -1
    }
}

function Get-PHP-Versions-List {
    param ($available = $false, $term = $null, $arch = $null, $buildType = $null)

    if ($available) {
        $result = Get-Available-PHP-Versions -term $term -arch $arch -buildType $buildType
    } else {
        $result = Show-Installed-PHP-Versions -term $term -arch $arch -buildType $buildType
    }

    return $result
}
