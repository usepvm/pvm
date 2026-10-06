
function Get-LatestPHPVersion {
    param ($arch = $null, $buildType = $null)

    try {
        $versionsList = Get-OrUpdateCache -cacheFileName 'latest_php_versions' -compute {
            return Show-SpinnerWhileJob -scriptBlock {
                $urls = Get-SourceUrls
                $allVersions = @()

                foreach ($key in $urls.Keys) {
                    try {
                        $url = $urls[$key]
                        $allVersions += Get-LatestPHPVersionFromUrl -url $url
                    } catch {
                        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get latest PHP version from $url"; exception = $_ }
                        continue
                    }
                }

                return @{ pvmData = $allVersions }
            } -rethrow $true
        }

        if ($arch) {
            $versionsList = $versionsList | Where-Object -FilterScript { $_.arch -eq $arch }
        }
        if ($buildType) {
            $versionsList = $versionsList | Where-Object -FilterScript { $_.buildType -eq $buildType }
        }

        # Sort by version number (descending) and return the first one
        $latest = $versionsList | Sort-Object -Property { [version]$_.version } -Descending | Select-Object -First 1

        return $latest
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get latest PHP version"; exception = $_ }
        return $null
    }
}

function Get-LatestPHPVersionFromUrl {
    param ($url)

    try {
        $html = Invoke-WebRequestWrapper -uri $url
        $links = $html.Links

        $allUrlVersions = @()
        $null = $links | Where-Object -FilterScript {
            if (-not $_.href) { return $false }
            if ($_.href -match 'php-debug') { return $false }
            if ($_.href -match 'php-devel') { return $false }
            if ($_.href -notmatch 'php-\d+(\.\d+)*-(?:nts-)?win.*\.zip$') { return $false }

            $version = $_.href -replace '/downloads/releases/archives/|/downloads/releases/|php-|-nts|-Win.*|.zip', ''
            $fileName = $_.href -split '/'
            $fileName = $fileName[$fileName.Count - 1]
            $allUrlVersions += @{
                href      = $_.href
                version   = $version
                fileName  = $fileName
                buildType = if ($fileName -match 'nts') { 'NTS' } else { 'TS' }
                arch      = ($fileName -replace '.*\b(x64|x86)\b.*', '$1')
            }
        }

        return $allUrlVersions
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get latest PHP version from $url"; exception = $_ }
        return @()
    }
}

function Get-PHPVersions {
    param ($version, $arch = $null, $buildType = $null)

    try {
        Show-Message -message "`nLoading the matching versions..."

        $fetchedVersionsGrouped = Get-PHPListToInstall

        if (Test-HasNoData -data $fetchedVersionsGrouped) {
            Show-Error -message "`nNo PHP versions found in the source. Please check your internet connection or the source URLs."
            return @{}
        }

        if ((Test-HasNoData -data $fetchedVersionsGrouped.Archives) -and (Test-HasNoData -data $fetchedVersionsGrouped.Releases)) {
            Show-Error -message "`nNo PHP versions found in the source. Please check your internet connection or the source URLs."
            return @{}
        }

        $fetchedVersions = [ordered]@{}
        $found = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        $fetchedVersionsGrouped.PSObject.Properties | ForEach-Object -Process {
            $searchResult = $_.Value | Where-Object -FilterScript {
                $_.version -like "$version*" -and
                (($null -eq $arch) -or ($_.arch -eq $arch)) -and
                (($null -eq $buildType) -or ($_.buildType -eq $buildType))
            }

            if ($searchResult -and $searchResult.Count -ne 0) {
                $filteredVersions = @()
                $searchResult | ForEach-Object -Process {
                    if ($found.Add($_.link)) {
                        $filteredVersions += @{
                            href      = $_.link
                            version   = $_.version
                            fileName  = $_.fileName
                            buildType = $_.buildType
                            arch      = $_.arch
                        }
                    }
                }

                if ($filteredVersions.Count -gt 0) {
                    $fetchedVersions[$_.Name] = $filteredVersions
                }
            }
        }

        return $fetchedVersions
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get PHP versions"; exception = $_ }
        return @{}
    }
}

function Get-PHP {
    param ($versionObject)

    try {
        $fileName = $versionObject.fileName
        $version = $versionObject.version
        $buildType = $versionObject.buildType
        $arch = $versionObject.arch

        $result = Test-DownloadPrerequisites -url $versionObject.href -minimumFreeSpaceMB $Global:PVMConfig.env.MIN_PHP_INSTALL_FREE_SPACE_MB
        if (-not $result -or -not $result.temporaryDirectory) {
            Write-Color -message "`n$($result.message)" -foreColor $result.color
            return $null
        }

        Show-Info -message "`nDownloading PHP $version ($buildType $arch)... ($($result.sizeMB) MB)"

        $temporaryDirectory = $result.temporaryDirectory
        $downloadPath = Get-RemoteFile -url $versionObject.href -destinationPath "$temporaryDirectory\$fileName"

        return @{ downloadPath = $downloadPath; temporaryDirectory = $temporaryDirectory; success = [bool]$downloadPath }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to download PHP version $($versionObject.version)"; exception = $_ }
        return $null
    }
}

function Expand-AndConfigurePHP {
    param ($path, $fileNamePath)

    try {
        Remove-ItemWrapper -path $fileNamePath

        $code = Expand-Zip -zipPath $path -extractPath $fileNamePath -deleteZipAfter $true
        if ($code -ne 0) {
            return -1
        }

        $iniCandidates = @(
            'php.ini-development',
            'php.ini-production',
            'php.ini-recommended',
            'php.ini-dist'
        )
        foreach ($candidate in $iniCandidates) {
            if (Test-FileExists -path "$fileNamePath\$candidate") {
                Copy-ItemWrapper -path "$fileNamePath\$candidate" -destination "$fileNamePath\php.ini"
                break
            }
        }

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to extract and configure PHP from $path"; exception = $_ }
        return -1
    }
}

function Set-Opcache {
    param ($version, $phpPath)

    try {
        Show-Message -message "`nConfiguring Opcache..."

        $phpIniPath = "$phpPath\php.ini"
        if (Test-FileNotExists -path $phpIniPath) {
            Show-Error -message "`nphp.ini not found at: $phpIniPath"
            return -1
        }

        $phpIniContent = Get-ContentWrapper -path $phpIniPath
        $phpIniContent = $phpIniContent | ForEach-Object -Process {
            $_ -replace '^\s*;\s*(extension_dir\s*=.*"ext")', '$1' `
                -replace '^\s*;\s*(opcache\.enable\s*=\s*\d+)', '$1' `
                -replace '^\s*;\s*(opcache\.enable_cli\s*=\s*\d+)', '$1'
        }
        Set-ContentWrapper -path $phpIniPath -value $phpIniContent
        Show-Success -message "`nOpcache configured successfully for PHP version $version"

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to enable opcache for PHP at $phpPath"; exception = $_ }
        Show-Error -message "`nFailed to enable opcache for PHP version $version"
        return -1
    }
}

function Select-Version {
    param ($matchingVersions, $version, $arch = $null, $buildType = $null)

    $matchingVersionsPartialList = [ordered]@{}
    $matchingVersions.GetEnumerator() | ForEach-Object -Process {
        $matchingVersionsPartialList[$_.Key] = $_.Value | Select-Object -Last $Global:PVMConfig.env.DEFAULT_PARTIAL_LIST_SIZE
    }
    $matchingKeys = $matchingVersions.Values | Where-Object -FilterScript { $_.Count -gt 0 }

    if ($matchingKeys.Length -eq 1) {
        # There is exactly one key with one item
        $selectedVersionObject = $matchingKeys
    } else {
        $text = "`nMatching PHP versions: $version"
        if ($null -ne $arch) {
            $text += " $arch"
        }
        if ($null -ne $buildType) {
            $text += " $buildType"
        }
        Show-Message -message $text
        $index = 0
        $matchingVersionsPartialList.GetEnumerator() | ForEach-Object -Process {
            $key = $_.Key
            $versionsList = $_.Value
            if ($versionsList.Length -eq 0) {
                return
            }
            Show-Message -message "`n$key versions:`n"
            $versionsList | ForEach-Object -Process {
                $_ | Add-Member -NotePropertyName 'index' -NotePropertyValue $index -Force
                Show-Message -message " [$index] $($_.version) $($_.arch) $($_.buildType)"
                $index++
            }
        }

        $msg = "`nThis is a partial list (latest matches only). For the complete list, visit:"
        $msg += "`n Releases : $($Global:PVMConfig.links.phpWinReleases)"
        $msg += "`n Archives : $($Global:PVMConfig.links.phpWinArchives)"
        Show-Info -message $msg
        $selectedVersionInput = Read-HostWrapper -prompt "`nEnter the [number] of your selection (or press Enter to cancel)" -notifyUser

        if (-not $selectedVersionInput) {
            return $null
        }

        $selectedVersionObject = $matchingVersionsPartialList.GetEnumerator() | ForEach-Object -Process {
            $_.Value | Where-Object -FilterScript {
                $_.index -eq $selectedVersionInput
            }
        }
    }

    if (-not $selectedVersionObject) {
        Show-Error -message "`nNo matching version found for '$selectedVersionInput'."
        return $null
    }

    return $selectedVersionObject
}

function Install-PHP {
    param ($version, $arch = $null, $buildType = $null)

    try {
        $foundInstalledVersions = Get-MatchingPHPVersions -version $version

        if ($foundInstalledVersions) {
            if ($version -match '^(\d+)(?:\.(\d+))?') {
                $currentVersion = Get-CurrentPHPVersion
                $familyVersion = $matches[0]
                Show-Message -message "`nOther versions from the $familyVersion.x family are available:"
                $maxNameLength = ($foundInstalledVersions.version | Measure-Object -Maximum Length).Maximum + ($Global:PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
                $foundInstalledVersions | ForEach-Object -Process {
                    $versionNumber = $_.version
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
                    $metaData = $metaData.Trim()
                    $versionNumber = "$versionNumber ".PadRight($maxNameLength, '.')
                    Show-Message -message " $versionNumber $metaData $isCurrent"
                }
                $response = Read-HostWrapper -prompt "`nWould you like to install another version from the $familyVersion.x ? (y/n)"
                if (Test-NoResponse -response $response) {
                    Write-Gray -message 'Installation cancelled'
                    return -1
                }
                $version = $familyVersion
            }
        }

        $matchingVersions = Get-PHPVersions -version $version -arch $arch -buildType $buildType

        if ($matchingVersions.Count -eq 0) {
            $msg = "No matching PHP versions found for '$version', Check one of the following:"
            $msg += "`n- Ensure the version is correct."
            $msg += "`n- Check your internet connection or the source URL."
            $msg += "`n- Use 'pvm list available' to see available versions."
            $msg += "`n- If you are trying to install a version that was announced recently, it may not be available for download yet."

            Show-Error -message $msg
            return -1
        }

        $selectedVersionObject = Select-Version -matchingVersions $matchingVersions -version $version -arch $arch -buildType $buildType
        if (-not $selectedVersionObject) {
            Write-Gray -message 'Installation cancelled'
            return -1
        }

        if (Test-PHPVersionInstalled -version $selectedVersionObject) {
            $message = "Version '$($selectedVersionObject.version)' already installed"
            $message += "`nRun: pvm use $($selectedVersionObject.version)"
            Write-Gray -message $message
            return -1
        }

        $downloadStatus = Get-PHP -versionObject $selectedVersionObject
        if (-not $downloadStatus -or $downloadStatus.success -eq $false) {
            Show-Error -message "`nFailed to download PHP version $($selectedVersionObject.version)"
            if ($downloadStatus -and $downloadStatus.temporaryDirectory) {
                Remove-ItemWrapper -path $downloadStatus.temporaryDirectory
            }
            return -1
        }

        $downloadPath = $downloadStatus.downloadPath
        Show-Message -message "`nExtracting the downloaded zip ..."
        $phpDirectoryName = "$($selectedVersionObject.version)_$($selectedVersionObject.buildType)_$($selectedVersionObject.arch)"
        $phpInstallPath = "$($Global:PVMConfig.paths.directories.php)\$phpDirectoryName"
        $code = Expand-AndConfigurePHP -path $downloadPath -fileNamePath $phpInstallPath

        Remove-ItemWrapper -path $downloadStatus.temporaryDirectory

        if ($code -ne 0) {
            Show-Error -message "`nFailed to extract PHP version $($selectedVersionObject.version)"
            Remove-ItemWrapper -path $phpInstallPath
            return -1
        }

        if (Test-FileNotExists -path "$phpInstallPath\php.ini") {
            Show-Error -message "`nFailed to find php.ini for PHP version $($selectedVersionObject.version)"
            Remove-ItemWrapper -path $phpInstallPath
            return -1
        }

        $null = Set-Opcache -version $selectedVersionObject.version -phpPath $phpInstallPath

        $null = Update-InstalledPHPVersionsCache

        $message = "`nPHP $($selectedVersionObject.version) installed successfully at: '$phpInstallPath'"
        $message += "`nRun 'pvm use $($selectedVersionObject.version)' to use this version"
        Show-Success -message $message

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to install PHP version $version"; exception = $_ }
        Show-Error -message "`nFailed to install PHP version $version"
        return -1
    }
}
