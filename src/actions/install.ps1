
function Get-PHP-Versions-From-Url {
    param ($url, $version)

    try {
        $html = Invoke-WebRequest -Uri $url
        $links = $html.Links

        # Filter the links to find versions that match the given version
        $filteredLinks = $links | Where-Object {
            $_.href -match "php-$version(\.\d+)*-win" -and
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
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-PHP-Versions-From-Url : Failed to fetch versions from $url" -data $_.Exception.Message
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
            if ($fetched.Count -gt 0) {
                $sysArch = if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') { 'x64' } else { 'x86' }
                $fetched = $fetched | Where-Object { $_.href -match "$sysArch" }

                if ($found -notcontains $fetched.fileName) {
                    $fetchedVersions[$key] = $fetched | Select-Object -Last 5
                    $found += $fetchedVersions[$key] | ForEach-Object { $_.fileName }
                }
            }
        }

        return $fetchedVersions
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-PHP-Versions : Failed to get PHP versions" -data $_.Exception.Message
        return @{}
    }
}

function Display-Version-List {
    param ($matchingVersions)

    Write-Host "`nMatching PHP versions:"
    try {
        $matchingVersions.GetEnumerator() | ForEach-Object {
            $key = $_.Key

            $versionsList = $_.Value
            Write-Host "`n$key versions:`n"
            $versionsList | ForEach-Object {
                $versionItem = $_.version -replace '/downloads/releases/archives/|/downloads/releases/|php-|-Win.*|.zip', ''
                Write-Host "  $versionItem"
            }
        }
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Display-Version-List : Failed to display version list" -data $_.Exception.Message
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
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Download-PHP-From-Url : Failed to download PHP from $url" -data $_.Exception.Message
        return $null
    }
}

function Download-PHP {
    param ($versionObject, $customDir = $null)

    try {
        $urls = Get-Source-Urls

        $fileName = $versionObject.fileName
        $version = $versionObject.version

        $destination = "$STORAGE_PATH\php"
        if ($customDir) {
            $destination = $customDir
        }
        Make-Directory -path $destination

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
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Download-PHP : Failed to download PHP version $versionObject.version" -data $_.Exception.Message
    }
    return $null
}

function Extract-Zip {
    param ($zipPath, $extractPath)

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractPath)
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Extract-Zip : Failed to extract zip file from $zipPath" -data $_.Exception.Message
    }
}

function Extract-And-Configure {
    param ($path, $fileNamePath)

    try {
        Remove-Item -Path $fileNamePath -Recurse -Force
        Extract-Zip -zipPath $path -extractPath $fileNamePath
        Copy-Item -Path "$fileNamePath\php.ini-development" -Destination "$fileNamePath\php.ini"
        Remove-Item -Path $path
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Extract-And-Configure : Failed to extract and configure PHP from $path" -data $_.Exception.Message
    }
}


function getXdebugConfigV2 {
    param($XDebugPath)

    return @"

        [xdebug]
        zend_extension="$XDebugPath"
        xdebug.remote_enable=1
        xdebug.remote_host=127.0.0.1
        xdebug.remote_port=9000
"@
}

function getXdebugConfigV3 {
    param($XDebugPath)

    return @"

        [xdebug]
        zend_extension="$XDebugPath"
        xdebug.mode=debug
        xdebug.client_host=127.0.0.1
        xdebug.client_port=9003
"@
}

function Config-XDebug {
    param ($version, $phpPath)

    try {

        $phpIniPath = "$phpPath\php.ini"
        if (-not (Test-Path $phpIniPath)) {
            Write-Host "php.ini not found at: $phpIniPath"
            return
        }

        $phpIniContent = Get-Content $phpIniPath
        $phpIniContent = $phpIniContent | ForEach-Object {
            $_ -replace '^\s*;\s*(extension_dir\s*=.*"ext")', '$1'
        }
        Set-Content -Path $phpIniPath -Value $phpIniContent -Encoding UTF8

        # Fetch xdebug links
        $baseUrl = "https://xdebug.org"
        $url = "$baseUrl/download/historical"
        $xDebugList = Get-XDebug-FROM-URL -url $url -version $version
        # Get the latest xdebug version
        if ($xDebugList.Count -eq 0) {
            Write-Host "`nNo xdebug version found for $version"
            return
        }
        $xDebugSelectedVersion = $xDebugList[0]

        Make-Directory -path "$phpPath\ext"

        Write-Host "`nDownloading XDEBUG $($xDebugSelectedVersion.xDebugVersion)..."
        Invoke-WebRequest -Uri "$baseUrl/$($xDebugSelectedVersion.href)" -OutFile "$phpPath\ext\$($xDebugSelectedVersion.fileName)"
        # config xdebug in the php.ini file
        $xDebugConfig = getXdebugConfigV2 -XDebugPath $($xDebugSelectedVersion.fileName)
        if ($xDebugSelectedVersion.xDebugVersion -like "3.*") {
            $xDebugConfig = getXdebugConfigV3 -XDebugPath $($xDebugSelectedVersion.fileName)
        }

        Write-Host "`nConfigure XDEBUG with PHP..."
        $xDebugConfig = $xDebugConfig -replace "\ +"
        Add-Content -Path $phpIniPath -Value $xDebugConfig
        Write-Host "`nXDEBUG configured successfully for PHP version $version"
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Config-XDebug : Failed to configure XDebug for PHP version $version" -data $_.Exception.Message
        Write-Host "`nFailed to configure XDebug for PHP version $version"
    }
}

function Get-XDebug-FROM-URL {
    param ($url, $version)

    try {
        $html = Invoke-WebRequest -Uri $url
        $links = $html.Links

         # Filter the links to find versions that match the given version
         $filteredLinks = $links | Where-Object {
            $_.href -match "php_xdebug-[\d\.]+-$version-.*\.dll" -and
            $_.href -notmatch "nts"
        }

        # Return the filtered links (PHP version names)
        $formattedList = @()
        $filteredLinks = $filteredLinks | ForEach-Object {
            # $version = $_.href -replace '/downloads/releases/archives/|/downloads/releases/|php-|-Win.*|.zip', ''
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
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-XDebug-FROM-URL : Failed to fetch xdebug versions from $url" -data $_.Exception.Message
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
            return
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
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Enable-Opcache : Failed to enable opcache for PHP at $phpPath" -data $_.Exception.Message
        Write-Host "`nFailed to enable opcache for PHP version $version"
    }
}

function Install-PHP {
    param ($version, $customDir = $null, $includeXDebug = $false, $enableOpcache = $false)

    if (Is-PHP-Version-Installed -version $version) {
        Write-Host "`nphp $version is already installed, run 'pvm use $version' to use it."
        exit(1)
    }

    try {
        Write-Host "`nLoading the matching versions..."
        $matchingVersions = Get-PHP-Versions -version $version

        if ($matchingVersions.Count -eq 0) {
            $msg = "`nNo matching PHP versions found for '$version', Check one of the following:"
            $msg += "`n- Ensure the version is correct."
            $msg += "`n- Check your internet connection or the source URL."
            $msg += "`n- Use 'pvm list available' to see available versions."
            Write-Host $msg
            exit -1
        }

        $selectedVersionObject = $null

        if ($matchingVersions.Count -gt 1) {
            # Display matching versions
            Display-Version-List -matchingVersions $matchingVersions

            # Prompt user to choose the version
            $selectedVersionInput = Read-Host "`nEnter the exact version to install (or press Enter to cancel)"

            if (-not $selectedVersionInput) {
                Write-Host "`nInstallation cancelled."
                exit -1
            }

            foreach ($entry in $matchingVersions.GetEnumerator()) {
                $selectedVersionObject = $entry.Value | Where-Object { $_.version -eq $selectedVersionInput }
                if ($selectedVersionObject) {
                    break
                }
            }
        }

        if (-not $selectedVersionObject) {
            $matchingVersions.GetEnumerator() | ForEach-Object {
                $selectedVersionObject = $_.Value | Select-Object -Last 1
            }

            if (-not $selectedVersionObject) {
                Write-Host "`nNo matching version found for '$version'."
                exit -1
            }
        }

        $destination = Download-PHP -version $selectedVersionObject -customDir $customDir

        if (-not $destination) {
            Write-Host "`nFailed to download PHP version $version."
            exit -1
        }

        Write-Host "`nExtracting the downloaded zip ..."
        $fileName = $selectedVersionObject.fileName
        $phpDirectoryName = $fileName -replace ".zip",""
        Extract-And-Configure -path "$destination\$fileName" -fileNamePath "$destination\$phpDirectoryName"

        if ($enableOpcache) {
            Enable-Opcache -version $version -phpPath "$destination\$phpDirectoryName"
        }

        if ($includeXDebug) {
            $version = ($selectedVersionObject.version -split '\.')[0..1] -join '.'
            Config-XDebug -version $version -phpPath "$destination\$phpDirectoryName"
        }

        Write-Host "`nAdding the PHP to the environment variables ..."
        $phpVersionNumber = $selectedVersionObject.version
        $phpEnvVarName = "php$phpVersionNumber"
        # Set-Php-Env -name $phpEnvVarName -value "$destination\$selectedVersion"
        $phpPath = "$destination\$phpDirectoryName"
        & "$PVMRoot\pvm" set $phpEnvVarName $phpPath
        Write-Host "`nRun 'pvm use $phpVersionNumber' to use this version"

        return 0
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Install-PHP : Failed to install PHP version $version" -data $_.Exception.Message
        return -1
    }
}
