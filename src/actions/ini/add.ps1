
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
        $html = Get-Web-Response -uri $url
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
                href          = $_.href
                version       = $version
                xDebugVersion = $xDebugVersion;
                arch          = if ($fileName -match '(x86_64|x64)(?=\.dll$)') { 'x64' } else { 'x86' }
                buildType     = if ($fileName -match '(?i)(?:^|-)nts(?:-|\.dll$)') { 'NTS' } else { 'TS' }
                compiler      = if ($fileName -match '(?i)\b(vs|vc)\d+\b') { $matches[0].ToUpper() } else { 'unknown' }
                fileName      = $fileName;
                outerHTML     = $_.outerHTML
            }
        }

        return $formattedList
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to fetch xdebug versions from $url"; exception = $_ }
        return @()
    }
}

function Get-PrereleaseSortKey {
    param ($Name)

    $baseVersionParts = ($Name -replace '(alpha|beta|rc).*', '') -split '\.'
    [int64]$versionScore = 0
    for ($i = 0; $i -lt 3; $i++) {
        $part = if ($i -lt $baseVersionParts.Count) { [int64]$baseVersionParts[$i] } else { 0 }
        $versionScore = ($versionScore * 1000) + $part
    }

    $weight = if ($Name -match 'alpha') { 1 }
    elseif ($Name -match 'beta') { 2 }
    elseif ($Name -match 'rc') { 3 }
    else { 4 } # stable

    $number = if ($Name -match '(alpha|beta|rc)(\d+)') { [int64]$matches[2] } else { 9999 }

    return ($versionScore * 100000) + ($weight * 10000) + $number
}

function Install-XDebug-Extension {
    param ($iniPath, $skipConfirmation = $false)

    try {
        $currentVersionObj = Get-Current-PHP-Version
        $currentVersion = $currentVersionObj.version -replace '^(\d+\.\d+)\..*$', '$1'
        $xDebugList = Get-OrUpdateCache -cacheFileName "available_xdebug_versions_$currentVersion`_xdebug" -compute {
            Get-XDebug-FROM-URL -url $PVMConfig.links.xdebugHistorical -version $currentVersion
        }

        if ($null -eq $xDebugList -or $xDebugList.Count -eq 0) {
            Show-Error -message "`nNo match was found, check the '$($PVMConfig.paths.logError)' for any potentiel errors"
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
        Select-Object -First $PVMConfig.env.DEFAULT_PARTIAL_LIST_SIZE |
        Group-Object xDebugVersion |
        Sort-Object -Descending -Property @{ Expression = { Get-PrereleaseSortKey -Name $_.Name } } |
        ForEach-Object {
            $sortedGroup = $_.Group | Sort-Object `
            @{ Expression = { $_.buildType -eq 'NTS' }; Descending = $true },
            @{ Expression     = {
                    switch ($_.arch) {
                        'x86_64' { 2 }
                        'x64' { 2 }
                        'x86' { 1 }
                        default { 0 }
                    }
                }; Descending = $true
            }

            $sortedGroup | ForEach-Object {
                $_ | Add-Member -NotePropertyName 'index' -NotePropertyValue $index -Force
                $index++
            }

            $xDebugListGrouped[$_.Name] = $sortedGroup
        }

        $xDebugListGrouped.GetEnumerator() | ForEach-Object {
            Show-Message -message "`nXDebug $($_.Key)"
            $_.Value | ForEach-Object {
                $text = "PHP XDebug $($_.version) $($_.compiler) $($_.buildType) $($_.arch)"
                Show-Message -message " [$($_.index)] $text"
            }
        }
        Show-Message -message "`nThis is a partial list. For a complete list, visit: $($PVMConfig.links.xdebugHistorical)"

        $packageIndex = Read-Host -Prompt "`nInsert the [number] you want to install"
        $packageIndex = $packageIndex.Trim()
        if ([string]::IsNullOrWhiteSpace($packageIndex)) {
            Write-Gray -message "`nInstallation cancelled"
            return -1
        }

        $chosenItem = $xDebugListGrouped.GetEnumerator() | ForEach-Object {
            $_.Value | Where-Object {
                $_.index -eq $packageIndex
            }
        }
        if (-not $chosenItem) {
            Show-Error -message "`nYou chose the wrong index: $packageIndex"
            return -1
        }

        $null = Get-Web-Response -uri "$($PVMConfig.links.xdebugBase)/$($chosenItem.href.TrimStart('/'))" -outFile $PVMConfig.paths.php
        $phpPath = ($iniPath | Split-Path -Parent)

        if (-not $skipConfirmation) {
            if (Test-File-Exists -path "$phpPath\ext\$($chosenItem.fileName)") {
                $response = Read-Host -Prompt "`n$($chosenItem.fileName) already exists. Would you like to overwrite it? (y/n)"
                $response = $response.Trim()
                if ($response -ne 'y' -and $response -ne 'Y') {
                    Remove-Item -Path "$($PVMConfig.paths.storage)\php\$($chosenItem.fileName)"
                    Write-Gray -message "`nInstallation cancelled"
                    return -1
                }
            }
        }

        Move-Item -Path "$($PVMConfig.paths.storage)\php\$($chosenItem.fileName)" -Destination "$phpPath\ext"
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

        Show-Success -message "`nXDebug installed successfully"

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to install extension 'xdebug'"; exception = $_ }
        return -1
    }
}

function Add-Missing-PHPExtension-To-Ini {
    param ($iniPath, $extFileName, $enable = $true)

    try {
        if (Test-File-Not-Exists -path $iniPath) {
            Show-Error -Message "`nphp.ini file not found: $iniPath"
            return -1
        }

        $null = Backup-IniFile -iniPath $iniPath

        $phpDirectory = Split-Path -Path $iniPath -Parent
        $extDirectory = "$phpDirectory\ext"

        if (Test-Directory-Not-Exists -path $extDirectory) {
            Show-Error -Message "`nExtensions directory not found: $extDirectory"
            return -1
        }

        if (Test-File-Not-Exists -path "$extDirectory\$extFileName") {
            Show-Error -Message "`nExtension file not found: $extFileName"
            return -1
        }

        $lines = Get-Content -Path $iniPath
        foreach ($line in $lines) {
            if ($line -match "^(;)?\s*(zend_)?extension\s*=\s*$extFileName\s*") {
                Show-Warning -message "- Extension '$extFileName' already exists in php.ini"
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
        Set-Content -Path $iniPath -Value $lines -Encoding UTF8
        Show-Success -message "- '$extFileName' added successfully."

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to add extension '$extFileName'"; exception = $_ }
        return -1
    }
}

function Install-Extension {
    param ($iniPath, $extName, $skipConfirmation = $false)

    try {
        $currentVersionObj = Get-Current-PHP-Version
        $currentVersion = $currentVersionObj.version -replace '^(\d+\.\d+)\..*$', '$1'
        $extensionLinksObj = Get-Extension-From-URL -extName $extName -version $currentVersion

        if (($null -eq $extensionLinksObj) -or ($extensionLinksObj.Count -eq 0) -or ($null -eq $extensionLinksObj.data) -or ($extensionLinksObj.data.Count -eq 0)) {
            $extName = if ($extensionLinksObj) { $extensionLinksObj.extName } else { $extName }
            Show-Error -Message "`nNo packages found for $extName"
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
            Show-Error -Message "`nNo packages found for '$extName' matching current PHP architecture/build type"
            return -1
        }

        $extName = $extensionLinksObj.extName
        if ($extensionLinks.Length -eq 1) {
            $chosenItem = $($extensionLinks)
        } else {
            $extensionLinksGrouped = [ordered]@{}
            $index = 0
            $extensionLinks |
            Select-Object -First $PVMConfig.env.DEFAULT_PARTIAL_LIST_SIZE |
            Group-Object extVersion |
            Sort-Object -Descending -Property @{ Expression = { Get-PrereleaseSortKey -Name $_.Name } } |
            ForEach-Object {
                $sortedGroup = $_.Group | Sort-Object `
                @{ Expression = { $_.buildType -eq 'NTS' }; Descending = $true },
                @{ Expression     = {
                        switch ($_.arch) {
                            'x86_64' { 2 }
                            'x64' { 2 }
                            'x86' { 1 }
                            default { 0 }
                        }
                    }; Descending = $true
                }
                $sortedGroup | ForEach-Object {
                    $_ | Add-Member -NotePropertyName 'index' -NotePropertyValue $index -Force
                    $index++
                }

                $extensionLinksGrouped[$_.Name] = $sortedGroup
            }

            $extensionLinksGrouped.GetEnumerator() | ForEach-Object {
                Show-Message -message "`n$extName $($_.Key)"
                $_.Value | ForEach-Object {
                    $text = "PHP $extName $($_.version) $($_.compiler) $($_.buildType) $($_.arch)"
                    Show-Message -message " [$($_.index)] $text"
                }
            }
            Show-Info -message "`nThis is a partial list. For a complete list, visit: $($PVMConfig.links.peclPackageRoot)/$extName"

            $packageIndex = Read-Host -Prompt "`nInsert the [number] you want to install"
            $packageIndex = $packageIndex.Trim()
            if ([string]::IsNullOrWhiteSpace($packageIndex)) {
                Write-Gray -message "`nInstallation cancelled"
                return -1
            }

            $chosenItem = $extensionLinks | Where-Object { $_.index -eq $packageIndex }
        }

        if (-not $chosenItem) {
            Show-Error -Message "`nYou chose the wrong index: $packageIndex"
            return -1
        }

        $null = Get-Web-Response -uri $chosenItem.href -outFile $PVMConfig.paths.php
        $fileNamePath = ($chosenItem.href -replace "$($PVMConfig.links.peclWinExtDownload)/$extName/$($chosenItem.extVersion)/|.zip", '').Trim()
        $extractPath = "$($PVMConfig.paths.storage)\php\$fileNamePath"
        Expand-Zip -zipPath "$extractPath.zip" -extractPath $extractPath -deleteZipAfter $true
        $files = Get-ChildItem -Path $extractPath
        $extFile = $files | Where-Object {
            ($_.Name -match "^php_$extName.*\.dll$")
        }
        if (-not $extFile) {
            Show-Error -Message "`nFailed to find $extName"
            return -1
        }

        $phpPath = ($iniPath | Split-Path -Parent)

        if (-not $skipConfirmation) {
            if (Test-File-Exists -path "$phpPath\ext\$($extFile.Name)") {
                $response = Read-Host -Prompt "`n$($extFile.Name) already exists. Would you like to overwrite it? (y/n)"
                $response = $response.Trim()
                if ($response -ne 'y' -and $response -ne 'Y') {
                    Remove-Item -Path "$($PVMConfig.paths.storage)\php\$fileNamePath" -Force -Recurse
                    Write-Gray -message "`nInstallation cancelled"
                    return -1
                }
            }
        }

        Move-Item -Path $extFile.FullName -Destination "$phpPath\ext"
        Remove-Item -Path $extractPath -Force -Recurse
        $code = Add-Missing-PHPExtension-To-Ini -iniPath $iniPath -extFileName $extFile.Name -enable $false
        if ($code -ne 0) {
            Show-Error -Message "`nFailed to add $extName"
            return -1
        }
        Show-Success -message "`n$extName installed successfully"

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to install extension '$extName'"; exception = $_ }
        return -1
    }
}

function Install-IniExtension {
    param ($iniPath, $extNames, $skipConfirmation = $false)

    try {
        if ($extNames.Count -eq 0) {
            Show-Warning -message "`nPlease provide at least one extension name to install"
            return -1
        }

        $overallCode = 0
        foreach ($extName in $extNames) {
            if ($extName -like '*xdebug*') {
                $overallCode = Install-XDebug-Extension -iniPath $iniPath -skipConfirmation $skipConfirmation
            } else {
                $overallCode = Install-Extension -iniPath $iniPath -extName $extName -skipConfirmation $skipConfirmation
            }
        }

        return $overallCode
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to install '$($extNames -join ', ')'"; exception = $_ }
        return -1
    }
}
