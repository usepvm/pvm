
function Get-FromSource {
    try {
        $fetchedVersionsGrouped = Show-SpinnerWhileJob -scriptBlock {
            $urls = Get-SourceUrls
            $fetchedVersionsGrouped = @{}
            foreach ($key in $urls.Keys) {
                try {
                    $url = $urls[$key]
                    $html = Invoke-WebRequestWrapper -uri $url
                    $links = $html.Links

                    # Filter the links to find versions that match the given version
                    $filteredLinks = [System.Collections.Generic.List[object]]::new()
                    $null = $links | Where-Object -FilterScript {
                        if (-not $_.href) { return $false }
                        if ($_.href -match 'php-debug') { return $false }
                        if ($_.href -match 'php-devel') { return $false }
                        if ($_.href -notmatch "php-\d+\.\d+\.\d+(?:-\d+)?-(?:nts-)?Win32.*\.zip$") { return $false }

                        $fileName = $_.href -split '/'
                        $fileName = $fileName[$fileName.Count - 1]
                        $link = "$url/$($_.href)"

                        $filteredLinks.Add(@{
                            fileName = $fileName
                            version   = ($_.href -replace '/downloads/releases/archives/|/downloads/releases/|php-|-nts|-Win.*|\.zip', '')
                            arch      = ($fileName -replace '.*\b(x64|x86)\b.*', '$1')
                            buildType = if ($fileName -match 'nts') { 'NTS' } else { 'TS' }
                            link      = $link
                        })
                    }
                    # Return the filtered links (PHP version names)
                    if ($filteredLinks.Count -gt 0) {
                        $fetchedVersionsGrouped[$key] = $filteredLinks
                    }
                } catch {
                    $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to fetch PHP versions from source: '$url'"; exception = $_ }
                }
            }

            return @{ pvmData = $fetchedVersionsGrouped }
        } -rethrow $true

        return $fetchedVersionsGrouped
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to fetch PHP versions from source"; exception = $_ }
        return @{}
    }
}

function Get-PHPListToInstall {
    try {
        $fetchedVersionsGrouped = Get-OrUpdateCache -cacheFileName 'available_php_versions' -compute {
            return [pscustomobject] (Get-FromSource)
        }

        return $fetchedVersionsGrouped
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get fetch PHP versions"; exception = $_ }
        return @{}
    }
}

function Get-AvailablePHPVersions {
    param ($term = $null, $arch = $null, $buildType = $null)

    try {
        Show-Message -message "`nLoading available PHP versions..."

        $fetchedVersionsGrouped = Get-PHPListToInstall

        if (Test-HasNoData -data $fetchedVersionsGrouped) {
            Show-Error -message "`nNo PHP versions found in the source. Please check your internet connection or the source URLs."
            return -1
        }

        if ((Test-HasNoData -data $fetchedVersionsGrouped.Archives) -and (Test-HasNoData -data $fetchedVersionsGrouped.Releases)) {
            Show-Error -message "`nNo PHP versions found in the source. Please check your internet connection or the source URLs."
            return -1
        }

        $fetchedVersionsGroupedPartialList = @{}
        $fetchedVersionsGrouped.PSObject.Properties | ForEach-Object -Process {
            $searchResult = $_.Value | Where-Object -FilterScript {
                (($null -eq $arch) -or ($_.arch -eq $arch)) -and
                (($null -eq $buildType) -or ($_.buildType -eq $buildType)) -and
                (($null -eq $term) -or ($_.version -like "$term*"))
            }

            if ($searchResult -and $searchResult.Count -ne 0) {
                $fetchedVersionsGroupedPartialList[$_.Name] = $searchResult | Select-Object -Last $Global:PVMConfig.env.DEFAULT_PARTIAL_LIST_SIZE
            }
        }

        if ($fetchedVersionsGroupedPartialList.Count -eq 0) {
            Show-Error -message "`nNo PHP versions found matching '$term'"
            return -1
        }

        Show-Info -message "`nAvailable Versions"
        Write-Gray -message '------------------'

        $fetchedVersionsGroupedPartialList.GetEnumerator() |
            Sort-Object -Property Key |
            ForEach-Object -Process {
                $key = $_.Key
                $fetchedVersionsGroupe = $_.Value
                if ($fetchedVersionsGroupe.Length -eq 0) {
                    return
                }
                Show-Message -message "`n$key`n"
                $maxNameLength = ($fetchedVersionsGroupe.version | Measure-Object -Maximum Length).Maximum + ($Global:PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
                $fetchedVersionsGroupe | ForEach-Object -Process {
                    $versionNumber = "$($_.version) ".PadRight($maxNameLength, '.')
                    Show-Message -message "  $versionNumber $($_.arch) $($_.buildType)"
                }
            }

        $msg = "`nThis is a partial list. For a complete list, visit:"
        $msg += "`n Releases : $($Global:PVMConfig.links.phpWinReleases)"
        $msg += "`n Archives : $($Global:PVMConfig.links.phpWinArchives)"
        Show-Info -message $msg
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get available PHP versions"; exception = $_ }
        return -1
    }
}

function Show-InstalledPHPVersions {
    param ($term = $null, $arch = $null, $buildType = $null)

    try {
        $currentVersion = Get-CurrentPHPVersion
        $installedPhp = Get-InstalledPHPVersions -arch $arch -buildType $buildType

        if ($installedPhp.Count -eq 0) {
            Show-Error -message "`nNo PHP versions found"
            return -1
        }

        if ($term) {
            $installedPhp = $installedPhp | Where-Object -FilterScript { $_.version -like "$term*" }
            if ($installedPhp.Count -eq 0) {
                Show-Error -message "`nNo PHP versions found matching '$term'"
                return -1
            }
        }

        Show-Info -message "`nInstalled Versions: ($($installedPhp.Count))"
        Write-Gray -message '------------------'
        $duplicates = @()
        $maxNameLength = ($installedPhp.version | Measure-Object -Maximum Length).Maximum + ($Global:PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
        $installedPhp | ForEach-Object -Process {
            $versionNumber = $_.version
            $versionID = "$($_.version)_$($_.buildType)_$($_.arch)"
            if ($duplicates -notcontains $versionID) {
                $duplicates += $versionID
                $isCurrent = ''
                $metaData = ''
                if ($_.arch) {
                    $metaData += $_.arch + ' '
                }
                if ($_.buildType) {
                    $metaData += $_.buildType
                }
                if (Test-TwoPHPVersionsEqual -version1 $currentVersion -version2 $_) {
                    $isCurrent = '(Current)'
                }
                $versionNumber = "$versionNumber ".PadRight($maxNameLength, '.')
                Show-Message -message " $versionNumber $metaData $isCurrent"
            }
        }
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to display installed PHP versions"; exception = $_ }
        return -1
    }
}

function Get-PHPVersionsList {
    param ($available = $false, $term = $null, $arch = $null, $buildType = $null)

    if ($available) {
        $result = Get-AvailablePHPVersions -term $term -arch $arch -buildType $buildType
    } else {
        $result = Show-InstalledPHPVersions -term $term -arch $arch -buildType $buildType
    }

    return $result
}
