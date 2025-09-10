
function Get-PHP-Versions-From-Url {
    param ($url, $version)

    try {
        $html = Invoke-WebRequest -Uri $url
        $links = $html.Links

        # Filter the links to find versions that match the given version
        $filteredLinks = $links | Where-Object {
            $_.href -match "php-$version(\.\d+)*-win.*\.zip$" -and
            $_.href -notmatch "php-debug" -and
            $_.href -notmatch "php-devel" -and
            $_.href -notmatch "nts"
        }

        # Return the filtered links (PHP version names)
        $formattedList = @()
        $filteredLinks = $filteredLinks | ForEach-Object {
            $version = $_.href -replace '/downloads/releases/archives/|/downloads/releases/|php-|-Win.*|.zip', ''
            $fileName = $_.href -split "/"
            $fileName = $fileName[$fileName.Count - 1]
            $formattedList += @{ href = $_.href; version = $version; fileName = $fileName }
        }

        return $formattedList
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to fetch versions from $url"
            exception = $_
        }
        return @()
    }
}

function Get-PHP-Versions {
    param ($version)

    try {
        $urls = Get-Source-Urls
        $fetchedVersions = @{}
        $found = @()
        foreach ($key in $urls.Keys) {
            $fetched = Get-PHP-Versions-From-Url -url $urls[$key] -version $version
            if ($fetched.Count -eq 0) {
                continue
            }
            $sysArch = if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') { 'x64' } else { 'x86' }
            $fetched = $fetched | Where-Object { $_.href -match $sysArch }
            if ($fetched.Count -eq 0) {
                continue
            }

            $fetchedVersions[$key] = @()
            $fetched | ForEach-Object {    
                if ($found -notcontains $_.fileName) {
                    $fetchedVersions[$key] += $_
                    $found += $_.fileName
                }
            }
        }

        return $fetchedVersions
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to get PHP versions"
            exception = $_
        }
        return @{}
    }
}



function Download-PHP-From-Url {
    param ($destination, $url, $versionObject)

    try {
        # Download the selected PHP version
        $fileName = $versionObject.fileName
        Invoke-WebRequest -Uri $url -OutFile "$destination\$fileName"
        return $destination
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to download PHP from $url"
            exception = $_
        }
        return $null
    }
}

function Download-PHP {
    param ($versionObject)

    try {
        $urls = Get-Source-Urls

        $fileName = $versionObject.fileName
        $version = $versionObject.version

        $destination = "$STORAGE_PATH\php"
        $created = Make-Directory -path $destination
        if ($created -ne 0) {
            Write-Host "Failed to create directory $destination"
            return $null
        }

        Write-Host "`nDownloading PHP $version..."

        foreach ($key in $urls.Keys) {
            $_url = $urls[$key]
            $downloadUrl = "$_url/$fileName"
            $downloadedFilePath = Download-PHP-From-Url -destination $destination -url $downloadUrl -version $versionObject

            if ($downloadedFilePath) {
                return $downloadedFilePath
            }
        }
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to download PHP version $($versionObject.version)"
            exception = $_
        }
    }
    return $null
}

function Extract-Zip {
    param ($zipPath, $extractPath)

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractPath)
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to extract zip file from $zipPath"
            exception = $_
        }
    }
}

function Extract-And-Configure {
    param ($path, $fileNamePath)

    try {
        Remove-Item -Path $fileNamePath -Recurse -Force
        Extract-Zip -zipPath $path -extractPath $fileNamePath
        $iniCandidates = @(
            "php.ini-development",
            "php.ini-production",
            "php.ini-recommended",
            "php.ini-dist"
        )
        foreach ($candidate in $iniCandidates) {
            if (Test-Path "$fileNamePath\$candidate") {
                Copy-Item -Path "$fileNamePath\$candidate" -Destination "$fileNamePath\php.ini"
                break
            }
        }
        Remove-Item -Path $path
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to extract and configure PHP from $path"
            exception = $_
        }
    }
}


function getXdebugConfigV2 {
    param($XDebugPath)

    return @"

        [xdebug]
        ;zend_extension="$XDebugPath"
        xdebug.remote_enable=1
        xdebug.remote_host=127.0.0.1
        xdebug.remote_port=9000
"@
}

function getXdebugConfigV3 {
    param($XDebugPath)

    return @"

        [xdebug]
        ;zend_extension="$XDebugPath"
        xdebug.mode=debug
        xdebug.client_host=127.0.0.1
        xdebug.client_port=9003
"@
}

function Config-XDebug {
    param ($version, $phpPath)

    try {

        if ([string]::IsNullOrWhiteSpace($version) -or [string]::IsNullOrWhiteSpace($phpPath)) {
            Write-Host "`nVersion and PHP path cannot be empty!"
            return -1
        }
        
        if (-not (Test-Path $phpPath)) {
            Write-Host "$phpPath is not a valid path"
            return -1
        }

        $phpIniPath = "$phpPath\php.ini"
        if (-not (Test-Path $phpIniPath)) {
            Write-Host "php.ini not found at: $phpIniPath"
            return -1
        }

        $version = ($version -split '\.')[0..1] -join '.'

        # Fetch xdebug links
        $baseUrl = "https://xdebug.org"
        $url = "$baseUrl/download/historical"
        $xDebugList = Get-XDebug-FROM-URL -url $url -version $version
        # Get the latest xdebug version
        if ($xDebugList.Count -eq 0) {
            Write-Host "`nNo xdebug version found for $version"
            return -1
        }
        $xDebugSelectedVersion = $xDebugList | 
                                # Where-Object { $_.fileName -match "vs" } |
                                Sort-Object { [version]$_.xDebugVersion } -Descending |
                                Select-Object -First 1

        $created = Make-Directory -path "$phpPath\ext"
        if ($created -ne 0) {
            Write-Host "Failed to create directory '$phpPath\ext'"
            return -1
        }

        Write-Host "`nDownloading XDEBUG $($xDebugSelectedVersion.xDebugVersion)..."
        Invoke-WebRequest -Uri "$baseUrl/$($xDebugSelectedVersion.href.TrimStart('/'))" -OutFile "$phpPath\ext\$($xDebugSelectedVersion.fileName)"
        # config xdebug in the php.ini file
        $xDebugConfig = getXdebugConfigV2 -XDebugPath $($xDebugSelectedVersion.fileName)
        if ($xDebugSelectedVersion.xDebugVersion -like "3.*") {
            $xDebugConfig = getXdebugConfigV3 -XDebugPath $($xDebugSelectedVersion.fileName)
        }

        Write-Host "`nConfigure XDEBUG with PHP..."
        $xDebugConfig = $xDebugConfig -replace "\ +"
        Add-Content -Path $phpIniPath -Value $xDebugConfig
        Write-Host "`nXDEBUG configured successfully for PHP version $version"
        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to configure XDebug for PHP version $version"
            exception = $_
        }
        Write-Host "`nFailed to configure XDebug for PHP version $version"
        return -1
    }
}

function Get-XDebug-FROM-URL {
    param ($url, $version)

    try {
        $html = Invoke-WebRequest -Uri $url
        $links = $html.Links

         # Filter the links to find versions that match the given version
        $sysArch = if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') { 'x86_64' } else { '' }
        $filteredLinks = $links | Where-Object {
            $_.href -match "php_xdebug-[\d\.a-zA-Z]+-$version-.*$sysArch\.dll" -and
            $_.href -notmatch "nts"
        }

        # Return the filtered links (PHP version names)
        $formattedList = @()
        $filteredLinks = $filteredLinks | ForEach-Object {
            $fileName = $_.href -split "/"
            $fileName = $fileName[$fileName.Count - 1]
            $xDebugVersion = "2.0"
            if ($_.href -match "php_xdebug-([\d\.]+)") {
                $xDebugVersion = $matches[1]
            }
            $formattedList += @{ href = $_.href; version = $version; xDebugVersion = $xDebugVersion; fileName = $fileName }
        }

        return $formattedList
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to fetch xdebug versions from $url"
            exception = $_
        }
        return @()
    }

}

function Enable-Opcache {
    param ($version, $phpPath)

    try {
        Write-Host "`nEnabling Opcache for PHP..."

        $phpIniPath = "$phpPath\php.ini"
        if (-not (Test-Path $phpIniPath)) {
            Write-Host "php.ini not found at: $phpIniPath"
            return -1
        }

        $phpIniContent = Get-Content $phpIniPath
        $phpIniContent = $phpIniContent | ForEach-Object {
            $_ -replace '^\s*;\s*(extension_dir\s*=.*"ext")', '$1' `
               -replace '^\s*;\s*(zend_extension\s*=\s*opcache)', '$1' `
               -replace '^\s*;\s*(opcache\.enable\s*=\s*\d+)', '$1' `
               -replace '^\s*;\s*(opcache\.enable_cli\s*=\s*\d+)', '$1'
        }
        Set-Content -Path $phpIniPath -Value $phpIniContent -Encoding UTF8
        Write-Host "`nOpcache enabled successfully for PHP version $version"
        
        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to enable opcache for PHP at $phpPath"
            exception = $_
        }
        Write-Host "`nFailed to enable opcache for PHP version $version"
        return -1
    }
}

function Select-Version {
    param ($matchingVersions)

    $matchingVersionsPartialList = @{}
    $matchingVersions.GetEnumerator() | ForEach-Object {
        $matchingVersionsPartialList[$_.Key] = $_.Value | Select-Object -Last $LatestVersionCount
    }
    $matchingKeys = $matchingVersions.Values | Where-Object { $_.Count -gt 0 }
    
    if ($matchingKeys.Length -eq 1) {
        # There is exactly one key with one item
        $selectedVersionObject = $matchingKeys
    } else {
        Write-Host "`nMatching PHP versions:"
        $matchingVersionsPartialList.GetEnumerator() | ForEach-Object {
            $key = $_.Key
            $versionsList = $_.Value
            if ($versionsList.Length -eq 0) {
                return
            }
            Write-Host "`n$key versions:`n"
            $versionsList | ForEach-Object {
                $versionItem = $_.version -replace '/downloads/releases/archives/|/downloads/releases/|php-|-Win.*|.zip', ''
                Write-Host "  $versionItem"
            }
        }

        $msg = "`nThis is a partial list (latest matches only). For the complete list, visit:"
        $msg += "`n Releases : https://windows.php.net/downloads/releases"
        $msg += "`n Archives : https://windows.php.net/downloads/releases/archives"
        Write-Host $msg
        $selectedVersionInput = Read-Host "`nEnter the exact version to install (or press Enter to cancel)"
        $selectedVersionInput = $selectedVersionInput.Trim()

        if (-not $selectedVersionInput) {
            return $null
        }

        $selectedVersionObject = $matchingVersions.Values | ForEach-Object {
            $_ | Where-Object {
                $_.version -eq $selectedVersionInput 
            } 
        } | Where-Object { $_ } | Select-Object -First 1
    }

    if (-not $selectedVersionObject) {
        Write-Host "`nNo matching version found for '$selectedVersionInput'."
        return $null
    }

    return $selectedVersionObject
}

function Install-PHP {
    param ($version)

    try {
        if (Is-PHP-Version-Installed -version $version) {
            $message = "Version '$($version)' already installed."
            $message += "`nRun: pvm use $version"
            return @{ code = -1; message = $message }
        }

        $foundInstalledVersions = Get-Matching-PHP-Versions -version $version

        if ($foundInstalledVersions) {
            if ($version -match '^(\d+)(?:\.(\d+))?') {
                $currentVersion = Get-Current-PHP-Version
                if ($currentVersion -and $currentVersion.version) {
                    $currentVersion = $currentVersion.version
                }
                $familyVersion = $matches[0]
                Write-Host "`nOther versions from the $familyVersion.x family are available:"
                $foundInstalledVersions | ForEach-Object {
                    $versionNumber = $_
                    $isCurrent = ""
                    if ($currentVersion -eq $versionNumber) {
                        $isCurrent = "(Current)"
                    }
                    Write-Host " - $versionNumber $isCurrent"
                }
                $response = Read-Host "`nWould you like to install another version from the $familyVersion.x ? (y/n)"
                $response = $response.Trim()
                if ($response -ne "y" -and $response -ne "Y") {
                    return @{ code = -1; message = "Installation cancelled" }
                }
                $version = $familyVersion
            }
        }

        Write-Host "`nLoading the matching versions..."
        $matchingVersions = Get-PHP-Versions -version $version

        if ($matchingVersions.Count -eq 0) {
            $msg = "No matching PHP versions found for '$version', Check one of the following:"
            $msg += "`n- Ensure the version is correct."
            $msg += "`n- Check your internet connection or the source URL."
            $msg += "`n- Use 'pvm list available' to see available versions."
            $msg += "`n- If you are trying to install a version that was announced recently, it may not be available for download yet."
            return @{ code = -1; message = $msg }
        }

        $selectedVersionObject = Select-Version -matchingVersions $matchingVersions
        if (-not $selectedVersionObject) {
            return @{ code = -1; message = "Installation cancelled" }
        }

        if (Is-PHP-Version-Installed -version $selectedVersionObject.version) {
            $message = "Version '$($selectedVersionObject.version)' already installed"
            $message += "`nRun: pvm use $($selectedVersionObject.version)"
            return @{ code = -1; message = $message }
        }

        $destination = Download-PHP -version $selectedVersionObject

        if (-not $destination) {
            return @{ code = -1; message = "Failed to download PHP version $version"; color = "DarkYellow" }
        }

        Write-Host "`nExtracting the downloaded zip ..."
        Extract-And-Configure -path "$destination\$($selectedVersionObject.fileName)" -fileNamePath "$destination\$($selectedVersionObject.version)"

        $opcacheEnabled = Enable-Opcache -version $version -phpPath "$destination\$($selectedVersionObject.version)"

        $xdebugConfigured = Config-XDebug -version $selectedVersionObject.version -phpPath "$destination\$($selectedVersionObject.version)"

        $message = "`nPHP $($selectedVersionObject.version) installed successfully at: '$destination\$($selectedVersionObject.version)'"
        $message += "`nRun 'pvm use $($selectedVersionObject.version)' to use this version"

        return @{ code = 0; message = $message; color = "DarkGreen" }
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to install PHP version $version"
            exception = $_
        }
        return @{ code = -1; message = "Failed to install PHP version $version"; color = "DarkYellow" }
    }
}
