
function Get-Xdebug-Config-V2 {
    param ($XDebugPath)

    return @"

        [xdebug]
        ;zend_extension="$XDebugPath"
        xdebug.remote_enable=1
        xdebug.remote_host=127.0.0.1
        xdebug.remote_port=9000
"@
}

function Get-Xdebug-Config-V3 {
    param ($XDebugPath)

    return @"

        [xdebug]
        ;zend_extension="$XDebugPath"
        xdebug.mode=debug
        xdebug.client_host=127.0.0.1
        xdebug.client_port=9003
"@
}

function Get-XDebug-FROM-URL {
    param ($url, $version)

    try {
        $html = Invoke-WebRequest -Uri $url
        $links = $html.Links

        # Return the filtered links (PHP version names)
        $formattedList = @()
        $links | ForEach-Object {
            if (-not $_.href) { return }

            $fileName = [System.IO.Path]::GetFileName($_.href)

            if ($fileName -notmatch '^php_xdebug-.*\.dll$') { return }

            if ($fileName -notmatch "php_xdebug-[\d\.a-zA-Z]+-$version-") { return }

            $xDebugVersion = '2.0'
            if ($fileName -match 'php_xdebug-([^-]+)') {
                $xDebugVersion = $matches[1]
            }

            $formattedList += @{
                href = $_.href
                version = $version
                xDebugVersion = $xDebugVersion;
                arch = if ($fileName -match '(x86_64|x64)(?=\.dll$)') { 'x64' } else { 'x86' }
                buildType = if ($fileName -match '(?i)(?:^|-)nts(?:-|\.dll$)') { 'NTS' } else { 'TS' }
                compiler = if ($fileName -match '(?i)\b(vs|vc)\d+\b') { $matches[0].ToUpper() } else { 'unknown' }
                fileName = $fileName;
                outerHTML = $_.outerHTML
            }
        }

        return $formattedList
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to fetch xdebug versions from $url"; exception = $_ }
        return @()
    }
}

function Install-XDebug-Extension {
    param ($iniPath)

    try {
        $currentVersionObj = Get-Current-PHP-Version
        $currentVersion = $currentVersionObj.version -replace '^(\d+\.\d+)\..*$', '$1'
        $xDebugList = Get-OrUpdateCache -cacheFileName "available_xdebug_versions_$currentVersion" -compute {
            Get-XDebug-FROM-URL -url $XDEBUG_HISTORICAL_URL -version $currentVersion
        }

        if ($null -eq $xDebugList -or $xDebugList.Count -eq 0) {
            Write-Host -Object "`nNo match was found, check the '$LOG_ERROR_PATH' for any potentiel errors"
            return -1
        }

        $xDebugList = $xDebugList | Where-Object {
            if ($null -ne $currentVersionObj.arch) {
                if ($_.arch -ne $currentVersionObj.arch) { return $false }
            }

            if ($null -ne $currentVersionObj.buildType) {
                if ($_.buildType -ne $currentVersionObj.buildType) { return $false }
            }

            return $true
        }

        $xDebugListGrouped = [ordered]@{}
        $index = 0
        $xDebugList |
            Select-Object -First $DEFAULT_PARTIAL_LIST_SIZE |
            Group-Object xDebugVersion |
            Sort-Object `
                @{ Expression = {
                        # extract numeric version
                        [version]($_.Name -replace '(alpha|beta|rc).*','')
                }; Descending = $true },
                @{ Expression = {
                    # prerelease weight
                    if ($_.Name -match 'alpha') { 1 }
                    elseif ($_.Name -match 'beta') { 2 }
                    elseif ($_.Name -match 'rc') { 3 }
                    else { 4 } # stable
                }; Descending = $true },
                @{ Expression = {
                    # prerelease number (alpha3, rc2, etc)
                    if ($_.Name -match '(alpha|beta|rc)(\d+)') {
                        [int]$matches[2]
                    } else {
                        [int]::MaxValue
                    }
                }; Descending = $true } |
            ForEach-Object {
                $sortedGroup = $_.Group | Sort-Object `
                    @{ Expression = { $_.buildType -eq 'NTS' }; Descending = $true },
                    @{ Expression = {
                        switch ($_.arch) {
                            'x86_64' { 2 }
                            'x64'    { 2 }
                            'x86'    { 1 }
                            default  { 0 }
                        }
                    }; Descending = $true }

                $sortedGroup | ForEach-Object {
                    $_ | Add-Member -NotePropertyName 'index' -NotePropertyValue $index -Force
                    $index++
                }

                $xDebugListGrouped[$_.Name] = $sortedGroup
            }

        $xDebugListGrouped.GetEnumerator() | ForEach-Object {
            Write-Host -Object "`nXDebug $($_.Key)"
            $_.Value | ForEach-Object {
                $text = "PHP XDebug $($_.version) $($_.compiler) $($_.buildType) $($_.arch)"
                Write-Host -Object " [$($_.index)] $text"
            }
        }
        Write-Host -Object "`nThis is a partial list. For a complete list, visit: $XDEBUG_HISTORICAL_URL"

        $packageIndex = Read-Host -Prompt "`nInsert the [number] you want to install"
        $packageIndex = $packageIndex.Trim()
        if ([string]::IsNullOrWhiteSpace($packageIndex)) {
            Write-Host -Object "`nInstallation cancelled"
            return -1
        }

        $chosenItem = $xDebugListGrouped.GetEnumerator() | ForEach-Object {
            $_.Value | Where-Object {
                $_.index -eq $packageIndex
            }
        }
        if (-not $chosenItem) {
            Write-Host -Object "`nYou chose the wrong index: $packageIndex" -ForegroundColor DarkYellow
            return -1
        }

        Invoke-WebRequest -Uri "$XDEBUG_BASE_URL/$($chosenItem.href.TrimStart('/'))" -OutFile "$STORAGE_PATH\php"
        $phpPath = ($iniPath | Split-Path -Parent)
        if (Is-File-Exists -path "$phpPath\ext\$($chosenItem.fileName)") {
            $response = Read-Host -Prompt "`n$($chosenItem.fileName) already exists. Would you like to overwrite it? (y/n)"
            $response = $response.Trim()
            if ($response -ne 'y' -and $response -ne 'Y') {
                Remove-Item -Path "$STORAGE_PATH\php\$($chosenItem.fileName)"
                Write-Host -Object "`nInstallation cancelled"
                return -1
            }
        }
        Move-Item -Path "$STORAGE_PATH\php\$($chosenItem.fileName)" -Destination "$phpPath\ext"
        Remove-Item -Path "$STORAGE_PATH\php\$($chosenItem.fileName)"
        $xDebugConfig = Get-Xdebug-Config-V2 -XDebugPath $($chosenItem.fileName)
        if ($chosenItem.xDebugVersion -like '3.*') {
            $xDebugConfig = Get-Xdebug-Config-V3 -XDebugPath $($chosenItem.fileName)
        }
        # check existence of previous xdebug
        $iniContent = Get-Content -Path $iniPath
        $dllXDebugExists = $false
        for ($i = 0; $i -lt $iniContent.Count; $i++) {
            if ($iniContent[$i] -match '^(?<comment>;)?\s*zend_extension\s*=.*xdebug.*$') {
                $iniContent[$i] = $iniContent[$i] -replace '^(?<comment>;)?(\s*zend_extension\s*=).*$', "zend_extension='$($chosenItem.fileName)'"
                $dllXDebugExists = $true
            }
        }
        if ($dllXDebugExists) {
            Set-Content -Path $iniPath -Value $iniContent -Encoding UTF8
        } else {
            $xDebugConfig = $xDebugConfig -replace '\ +'
            Add-Content -Path $iniPath -Value $xDebugConfig
        }

        Write-Host -Object "`nXDebug installed successfully" -ForegroundColor DarkGreen

        return 0
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to install extension 'xdebug'"; exception = $_ }
        return -1
    }
}

function Add-Missing-PHPExtension-To-Ini {
    param ($iniPath, $extFileName, $enable = $true)

    try {
        if (Is-File-Not-Exists -path $iniPath) {
            Write-Host -Object "`nphp.ini file not found: $iniPath" -ForegroundColor DarkYellow
            return -1
        }

        Backup-IniFile $iniPath

        $phpDirectory = Split-Path -Path $iniPath -Parent
        $extDirectory = "$phpDirectory\ext"

        if (Is-Directory-Not-Exists -path $extDirectory) {
            Write-Host -Object "`nExtensions directory not found: $extDirectory" -ForegroundColor DarkYellow
            return -1
        }

        if (Is-File-Not-Exists -path "$extDirectory\$extFileName") {
            Write-Host -Object "`nExtension file not found: $extFileName" -ForegroundColor DarkYellow
            return -1
        }

        $lines = Get-Content -Path $iniPath
        foreach ($line in $lines) {
            if ($line -match "^(;)?\s*(zend_)?extension\s*=\s*$extFileName\s*") {
                Write-Host -Object "- Extension '$extFileName' already exists in php.ini" -ForegroundColor DarkGray
                return 0
            }
        }

        $commented = if ($enable) { '' } else { ';' }
        $isZendExtension = Get-Zend-Extensions-List | Where-Object { $extFileName -like "*$_*" }
        if ($isZendExtension) {
            $lines += "`n$commented" + "zend_extension=$extFileName"
        } else {
            $lines += "`n$commented" + "extension=$extFileName"
        }
        Set-Content -Path $iniPath $lines -Encoding UTF8
        Write-Host -Object "- '$extFileName' added successfully." -ForegroundColor DarkGreen

        return 0
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to add extension '$extFileName'"; exception = $_ }
        return -1
    }
}

function Install-Extension {
    param ($iniPath, $extName)

    try {
        $currentVersionObj = Get-Current-PHP-Version
        $currentVersion = $currentVersionObj.version -replace '^(\d+\.\d+)\..*$', '$1'
        $extensionLinksObj = Get-Extension-From-URL -extName $extName -version $currentVersion

        if (($null -eq $extensionLinksObj) -or ($extensionLinksObj.Count -eq 0) -or ($null -eq $extensionLinksObj.data) -or ($extensionLinksObj.data.Count -eq 0)) {
            $extName = if ($extensionLinksObj) { $extensionLinksObj.extName } else { $extName }
            Write-Host -Object "`nNo packages found for $extName" -ForegroundColor DarkYellow
            return -1
        }

        $extensionLinks = $extensionLinksObj.data | Where-Object {
            if ($null -ne $currentVersionObj.arch) {
                if ($_.arch -ne $currentVersionObj.arch) { return $false }
            }

            if ($null -ne $currentVersionObj.buildType) {
                if ($_.buildType -ne $currentVersionObj.buildType) { return $false }
            }

            return $true
        }

        if ($null -eq $extensionLinks -or $extensionLinks.Count -eq 0) {
            Write-Host -Object "`nNo packages found for '$extName' matching current PHP architecture/build type" -ForegroundColor DarkYellow
            return -1
        }

        $extName = $extensionLinksObj.extName
        if ($extensionLinks.Length -eq 1) {
            $chosenItem = $($extensionLinks)
        } else {
            $extensionLinksGrouped = [ordered]@{}
            $index = 0
            $extensionLinks |
                Select-Object -First $DEFAULT_PARTIAL_LIST_SIZE |
                Group-Object extVersion |
                Sort-Object `
                    @{ Expression = {
                        # extract numeric version
                        [version]($_.Name -replace '(alpha|beta|rc).*','')
                    }; Descending = $true },
                    @{ Expression = {
                        # prerelease weight
                        if ($_.Name -match 'alpha') { 1 }
                        elseif ($_.Name -match 'beta') { 2 }
                        elseif ($_.Name -match 'rc') { 3 }
                        else { 4 } # stable
                    }; Descending = $true },
                    @{ Expression = {
                        # prerelease number (alpha3, rc2, etc)
                        if ($_.Name -match '(alpha|beta|rc)(\d+)') {
                            [int]$matches[2]
                        } else {
                            [int]::MaxValue
                        }
                    }; Descending = $true } |
                ForEach-Object {
                    $sortedGroup = $_.Group | Sort-Object `
                        @{ Expression = { $_.buildType -eq 'NTS' }; Descending = $true },
                        @{ Expression = {
                            switch ($_.arch) {
                                'x86_64' { 2 }
                                'x64'    { 2 }
                                'x86'    { 1 }
                                default  { 0 }
                            }
                        }; Descending = $true }
                    $sortedGroup | ForEach-Object {
                        $_ | Add-Member -NotePropertyName 'index' -NotePropertyValue $index -Force
                        $index++
                    }

                    $extensionLinksGrouped[$_.Name] = $sortedGroup
                }

            $extensionLinksGrouped.GetEnumerator() | ForEach-Object {
                Write-Host -Object "`n$extName $($_.Key)"
                $_.Value | ForEach-Object {
                    $text = "PHP $extName $($_.version) $($_.compiler) $($_.buildType) $($_.arch)"
                    Write-Host -Object " [$($_.index)] $text"
                }
            }
            Write-Host -Object "`nThis is a partial list. For a complete list, visit: $PECL_PACKAGE_ROOT_URL/$extName"

            $packageIndex = Read-Host -Prompt "`nInsert the [number] you want to install"
            $packageIndex = $packageIndex.Trim()
            if ([string]::IsNullOrWhiteSpace($packageIndex)) {
                Write-Host -Object "`nInstallation cancelled"
                return -1
            }

            $chosenItem = $extensionLinks | Where-Object { $_.index -eq $packageIndex }
        }

        if (-not $chosenItem) {
            Write-Host -Object "`nYou chose the wrong index: $packageIndex" -ForegroundColor DarkYellow
            return -1
        }

        Invoke-WebRequest -Uri $chosenItem.href -OutFile "$STORAGE_PATH\php"
        $fileNamePath = ($chosenItem.href -replace "$PECL_WIN_EXT_DOWNLOAD_URL/$extName/$($chosenItem.extVersion)/|.zip",'').Trim()
        Extract-Zip -zipPath "$STORAGE_PATH\php\$fileNamePath.zip" -extractPath "$STORAGE_PATH\php\$fileNamePath"
        Remove-Item -Path "$STORAGE_PATH\php\$fileNamePath.zip"
        $files = Get-ChildItem -Path "$STORAGE_PATH\php\$fileNamePath"
        $extFile = $files | Where-Object {
            ($_.Name -match "^php_$extName.*\.dll$")
        }
        if (-not $extFile) {
            Write-Host -Object "`nFailed to find $extName" -ForegroundColor DarkYellow
            return -1
        }
        $phpPath = ($iniPath | Split-Path -Parent)
        if (Is-File-Exists -path "$phpPath\ext\$($extFile.Name)") {
            $response = Read-Host -Prompt "`n$($extFile.Name) already exists. Would you like to overwrite it? (y/n)"
            $response = $response.Trim()
            if ($response -ne 'y' -and $response -ne 'Y') {
                Remove-Item -Path "$STORAGE_PATH\php\$fileNamePath" -Force -Recurse
                Write-Host -Object "`nInstallation cancelled"
                return -1
            }
        }
        Move-Item -Path $extFile.FullName -Destination "$phpPath\ext"
        Remove-Item -Path "$STORAGE_PATH\php\$fileNamePath" -Force -Recurse
        $code = Add-Missing-PHPExtension-To-Ini -iniPath $iniPath -extFileName $extFile.Name -enable $false
        if ($code -ne 0) {
            Write-Host -Object "`nFailed to add $extName" -ForegroundColor DarkYellow
            return -1
        }
        Write-Host -Object "`n$extName installed successfully" -ForegroundColor DarkGreen

        return 0
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to install extension '$extName'"; exception = $_ }
        return -1
    }
}

function Install-IniExtension {
    param ($iniPath, $extNames)

    try {
        if ($extNames.Count -eq 0) {
            Write-Host -Object "`nPlease provide at least one extension name to install"
            return -1
        }

        $overallCode = 0
        foreach ($extName in $extNames) {
            if ($extName -like '*xdebug*') {
                $overallCode = Install-XDebug-Extension -iniPath $iniPath
            } else {
                $overallCode = Install-Extension -iniPath $iniPath -extName $extName
            }
        }

        return $overallCode
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to install '$($extNames -join ', ')'"; exception = $_ }
        return -1
    }
}
