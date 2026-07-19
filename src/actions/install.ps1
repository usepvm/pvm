
function Get-Latest-PHP-Version {
    param ($arch = $null, $buildType = $null)

    try {
        $versionsList = Get-OrUpdateCache -cacheFileName 'latest_php_versions' -compute {
            $urls = Get-Source-Urls
            $allVersions = @()

            foreach ($key in $urls.Keys) {
                $url = $urls[$key]
                try {
                    $html = Get-Web-Response -uri $url
                    $links = $html.Links

                    $filteredLinks = $links | Where-Object {
                        $_.href -match 'php-\d+(\.\d+)*-(?:nts-)?win.*\.zip$' -and
                        $_.href -notmatch 'php-debug' -and
                        $_.href -notmatch 'php-devel'
                    }

                    $filteredLinks | ForEach-Object {
                        $version = $_.href -replace '/downloads/releases/archives/|/downloads/releases/|php-|-nts|-Win.*|.zip', ''
                        $fileName = $_.href -split '/'
                        $fileName = $fileName[$fileName.Count - 1]
                        $allVersions += @{
                            href      = $_.href
                            version   = $version
                            fileName  = $fileName
                            BuildType = if ($fileName -match 'nts') { 'NTS' } else { 'TS' }
                            arch      = ($fileName -replace '.*\b(x64|x86)\b.*', '$1')
                        }
                    }
                } catch {
                    continue
                }
            }

            return $allVersions
        }

        if ($arch) {
            $versionsList = $versionsList | Where-Object { $_.arch -eq $arch }
        }
        if ($buildType) {
            $versionsList = $versionsList | Where-Object { $_.BuildType -eq $buildType }
        }

        # Sort by version number (descending) and return the first one
        $latest = $versionsList | Sort-Object { [version]$_.version } -Descending | Select-Object -First 1

        return $latest
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get latest PHP version"; exception = $_ }
        return $null
    }
}

function Get-PHP-Versions-From-Url {
    param ($url, $version)

    try {
        $html = Get-Web-Response -uri $url
        $links = $html.Links

        # Filter the links to find versions that match the given version
        $filteredLinks = $links | Where-Object {
            $_.href -match "php-$version(\.\d+)*-(?:nts-)?win.*\.zip$" -and
            $_.href -notmatch 'php-debug' -and
            $_.href -notmatch 'php-devel' # -and $_.href -notmatch "nts"
        }

        # Return the filtered links (PHP version names)
        $formattedList = @()
        $filteredLinks = $filteredLinks | ForEach-Object {
            $version = $_.href -replace '/downloads/releases/archives/|/downloads/releases/|php-|-nts|-Win.*|.zip', ''
            $fileName = $_.href -split '/'
            $fileName = $fileName[$fileName.Count - 1]
            $formattedList += @{
                href      = $_.href
                version   = $version
                fileName  = $fileName
                BuildType = if ($fileName -match 'nts') { 'NTS' } else { 'TS' }
                arch      = ($fileName -replace '.*\b(x64|x86)\b.*', '$1')
            }
        }

        return $formattedList
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to fetch versions from $url"; exception = $_ }
        return @()
    }
}

function Get-PHP-Versions {
    param ($version, $arch = $null, $buildType = $null)

    try {
        $urls = Get-Source-Urls
        $rawByKey = @{}

        foreach ($key in $urls.Keys) {
            $fetched = Get-PHP-Versions-From-Url -url $urls[$key] -version $version
            if ($fetched.Count -eq 0) {
                continue
            }
            if ($null -ne $arch) { $fetched = $fetched | Where-Object { $_.arch -eq $arch } }
            if ($null -ne $buildType) { $fetched = $fetched | Where-Object { $_.buildType -eq $buildType } }
            if ($fetched.Count -eq 0) { continue }
            $rawByKey[$key] = $fetched
        }

        $fetchedVersions = [ordered]@{}
        foreach ($key in $urls.Keys) {
            $fetchedVersions[$key] = @()
        }

        $found = @()
        foreach ($key in @('Releases', 'Archives')) {
            if (-not $rawByKey.ContainsKey($key)) {
                continue
            }
            $rawByKey[$key] | ForEach-Object {
                if ($found -notcontains $_.fileName) {
                    $fetchedVersions[$key] += $_
                    $found += $_.fileName
                }
            }
        }

        foreach ($key in @($fetchedVersions.Keys)) {
            if ($fetchedVersions[$key].Count -eq 0) {
                $fetchedVersions.Remove($key)
            }
        }

        return $fetchedVersions
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get PHP versions"; exception = $_ }
        return @{}
    }
}

function Download-PHP-From-Url {
    param ($destination, $url, $versionObject)

    try {
        # Download the selected PHP version
        $fileName = $versionObject.fileName
        $null = Get-Web-Response -uri $url -outFile "$destination\$fileName"
        return $destination
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to download PHP from $url"; exception = $_ }
        return $null
    }
}

function Download-PHP {
    param ($versionObject)

    try {
        $urls = Get-Source-Urls

        $fileName = $versionObject.fileName
        $version = $versionObject.version
        $buildType = $versionObject.BuildType
        $arch = $versionObject.arch

        $destination = $PVMConfig.paths.php
        $created = Make-Directory -path $destination
        if ($created -ne 0) {
            Print-Error -message "Failed to create directory $destination"
            return $null
        }

        Print-Info -message "`nDownloading PHP $version ($buildType $arch)..."

        foreach ($key in $urls.Keys) {
            $_url = $urls[$key]
            $downloadUrl = "$_url/$fileName"
            $downloadedFilePath = Download-PHP-From-Url -destination $destination -url $downloadUrl -version $versionObject

            if ($downloadedFilePath) {
                return $downloadedFilePath
            }
        }
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to download PHP version $($versionObject.version)"; exception = $_ }
    }
    return $null
}

function Extract-And-Configure {
    param ($path, $fileNamePath)

    try {
        Remove-Item -Path $fileNamePath -Recurse -Force
        Extract-Zip -zipPath $path -extractPath $fileNamePath -deleteZipAfter $true
        $iniCandidates = @(
            'php.ini-development',
            'php.ini-production',
            'php.ini-recommended',
            'php.ini-dist'
        )
        foreach ($candidate in $iniCandidates) {
            if (Is-File-Exists -path "$fileNamePath\$candidate") {
                Copy-Item -Path "$fileNamePath\$candidate" -Destination "$fileNamePath\php.ini"
                break
            }
        }
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to extract and configure PHP from $path"; exception = $_ }
    }
}

function Configure-Opcache {
    param ($version, $phpPath)

    try {
        Print-Message -message "`nConfiguring Opcache..."

        $phpIniPath = "$phpPath\php.ini"
        if (Is-File-Not-Exists -path $phpIniPath) {
            Print-Error -message "php.ini not found at: $phpIniPath"
            return -1
        }

        $phpIniContent = Get-Content -Path $phpIniPath
        $phpIniContent = $phpIniContent | ForEach-Object {
            $_ -replace '^\s*;\s*(extension_dir\s*=.*"ext")', '$1' `
                -replace '^\s*;\s*(opcache\.enable\s*=\s*\d+)', '$1' `
                -replace '^\s*;\s*(opcache\.enable_cli\s*=\s*\d+)', '$1'
        }
        Set-Content -Path $phpIniPath -Value $phpIniContent -Encoding UTF8
        Print-Success -message "`nOpcache configured successfully for PHP version $version"

        return 0
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to enable opcache for PHP at $phpPath"; exception = $_ }
        Print-Error -message "`nFailed to enable opcache for PHP version $version"
        return -1
    }
}

function Select-Version {
    param ($matchingVersions, $version, $arch = $null, $buildType = $null)

    $matchingVersionsPartialList = [ordered]@{}
    $matchingVersions.GetEnumerator() | ForEach-Object {
        $matchingVersionsPartialList[$_.Key] = $_.Value | Select-Object -Last $PVMConfig.env.DEFAULT_PARTIAL_LIST_SIZE
    }
    $matchingKeys = $matchingVersions.Values | Where-Object { $_.Count -gt 0 }

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
        Print-Message -message $text
        $index = 0
        $matchingVersionsPartialList.GetEnumerator() | ForEach-Object {
            $key = $_.Key
            $versionsList = $_.Value
            if ($versionsList.Length -eq 0) {
                return
            }
            Print-Message -message "`n$key versions:`n"
            $versionsList | ForEach-Object {
                $_ | Add-Member -NotePropertyName 'index' -NotePropertyValue $index -Force
                Print-Message -message " [$index] $($_.version) $($_.arch) $($_.BuildType)"
                $index++
            }
        }

        $msg = "`nThis is a partial list (latest matches only). For the complete list, visit:"
        $msg += "`n Releases : $($PVMConfig.links.phpWinReleases)"
        $msg += "`n Archives : $($PVMConfig.links.phpWinArchives)"
        Print-Message -message $msg
        $selectedVersionInput = Read-Host -Prompt "`nInsert the [number] matching the version to install (or press Enter to cancel)"
        $selectedVersionInput = $selectedVersionInput.Trim()

        if (-not $selectedVersionInput) {
            return $null
        }

        $selectedVersionObject = $matchingVersionsPartialList.GetEnumerator() | ForEach-Object {
            $_.Value | Where-Object {
                $_.index -eq $selectedVersionInput
            }
        }
    }

    if (-not $selectedVersionObject) {
        Print-Error -message "`nNo matching version found for '$selectedVersionInput'."
        return $null
    }

    return $selectedVersionObject
}

function Install-PHP {
    param ($version, $arch = $null, $buildType = $null)

    try {
        $foundInstalledVersions = Get-Matching-PHP-Versions -version $version

        if ($foundInstalledVersions) {
            if ($version -match '^(\d+)(?:\.(\d+))?') {
                $currentVersion = Get-Current-PHP-Version
                $familyVersion = $matches[0]
                Print-Message -message "`nOther versions from the $familyVersion.x family are available:"
                $maxNameLength = ($foundInstalledVersions.Version | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
                $foundInstalledVersions | ForEach-Object {
                    $versionNumber = $_.Version
                    $isCurrent = ''
                    $metaData = ''
                    if ($_.Arch) {
                        $metaData += $_.Arch + ' '
                    }
                    if ($_.BuildType) {
                        $metaData += $_.BuildType
                    }
                    if (Is-Two-PHP-Versions-Equal -version1 $currentVersion -version2 $_) {
                        $isCurrent = '(Current)'
                    }
                    $metaData = $metaData.Trim()
                    $versionNumber = "$versionNumber ".PadRight($maxNameLength, '.')
                    Print-Message -message " $versionNumber $metaData $isCurrent"
                }
                $response = Read-Host -Prompt "`nWould you like to install another version from the $familyVersion.x ? (y/n)"
                $response = $response.Trim()
                if ($response -ne 'y' -and $response -ne 'Y') {
                    return @{ code = -1; message = 'Installation cancelled'; color = 'Gray' }
                }
                $version = $familyVersion
            }
        }

        Print-Message -message "`nLoading the matching versions..."
        $matchingVersions = Get-PHP-Versions -version $version -arch $arch -buildType $buildType

        if ($matchingVersions.Count -eq 0) {
            $msg = "No matching PHP versions found for '$version', Check one of the following:"
            $msg += "`n- Ensure the version is correct."
            $msg += "`n- Check your internet connection or the source URL."
            $msg += "`n- Use 'pvm list available' to see available versions."
            $msg += "`n- If you are trying to install a version that was announced recently, it may not be available for download yet."
            return @{ code = -1; message = $msg; color = 'DarkYellow' }
        }

        $selectedVersionObject = Select-Version -matchingVersions $matchingVersions -version $version -arch $arch -buildType $buildType
        if (-not $selectedVersionObject) {
            return @{ code = -1; message = 'Installation cancelled'; color = 'Gray' }
        }

        if (Is-PHP-Version-Installed -version $selectedVersionObject) {
            $message = "Version '$($selectedVersionObject.version)' already installed"
            $message += "`nRun: pvm use $($selectedVersionObject.version)"
            return @{ code = -1; message = $message; color = 'Gray' }
        }

        $destination = Download-PHP -versionObject $selectedVersionObject

        if (-not $destination) {
            return @{ code = -1; message = "Failed to download PHP version $version"; color = 'DarkYellow' }
        }

        Print-Message -message "`nExtracting the downloaded zip ..."
        $phpDirectoryName = "$($selectedVersionObject.version)_$($selectedVersionObject.BuildType)_$($selectedVersionObject.arch)"
        Extract-And-Configure -path "$destination\$($selectedVersionObject.fileName)" -fileNamePath "$destination\$phpDirectoryName"

        $null = Configure-Opcache -version $version -phpPath "$destination\$phpDirectoryName"

        $message = "`nPHP $($selectedVersionObject.version) installed successfully at: '$destination\$phpDirectoryName'"
        $message += "`nRun 'pvm use $($selectedVersionObject.version)' to use this version"

        $null = Refresh-Installed-PHP-Versions-Cache

        return @{ code = 0; message = $message; color = 'DarkGreen' }
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to install PHP version $version"; exception = $_ }
        return @{ code = -1; message = "Failed to install PHP version $version"; color = 'DarkYellow' }
    }
}
