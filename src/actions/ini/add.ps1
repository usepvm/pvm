
function Select-ExtensionPackageLink {
    param ($extName, $extensionLinks)

    $extensionLinksGrouped = [ordered]@{}
    $index = 0
    $extensionLinks |
        Select-Object -First $PVMConfig.env.DEFAULT_PARTIAL_LIST_SIZE |
        Group-Object extVersion |
        Sort-Object -Descending -Property @{ Expression = { Get-PrereleaseSortKey -Name $_.Name } } |
        ForEach-Object -Process {
            $sortedGroup = $_.Group | Sort-Object -Property `
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
            $sortedGroup | ForEach-Object -Process {
                $_ | Add-Member -NotePropertyName 'index' -NotePropertyValue $index -Force
                $index++
            }

            $extensionLinksGrouped[$_.Name] = $sortedGroup
        }

    $extensionLinksGrouped.GetEnumerator() | ForEach-Object -Process {
        Show-Message -message "`n$extName $($_.Key)"
        $_.Value | ForEach-Object -Process {
            $text = "PHP $extName $($_.version) $($_.compiler) $($_.buildType) $($_.arch)"
            Show-Message -message " [$($_.index)] $text"
        }
    }

    $packageIndex = Read-HostWrapper -prompt "`nInsert the [number] you want to install"
    if ([string]::IsNullOrWhiteSpace($packageIndex)) {
        Write-Gray -message "`nInstallation cancelled"
        return $null
    }

    return ($extensionLinks | Where-Object -FilterScript { $_.index -eq $packageIndex })
}

function Get-XdebugConfigV2 {
    param ($XDebugPath)

    return @(
        '[xdebug]'
        ";zend_extension='$XDebugPath'"
        'xdebug.remote_enable=1'
        'xdebug.remote_host=127.0.0.1'
        'xdebug.remote_port=9000'
    )
}

function Get-XdebugConfigV3 {
    param ($XDebugPath)

    return @(
        '[xdebug]'
        ";zend_extension='$XDebugPath'"
        'xdebug.mode=debug'
        'xdebug.client_host=127.0.0.1'
        'xdebug.client_port=9003'
    )
}

function Get-XDebugFromUrl {
    param ($url, $version)

    try {
        $html = Invoke-WebRequestWrapper -uri $url
        $links = $html.Links

        # Return the filtered links (PHP version names)
        $formattedList = @()
        $links | ForEach-Object -Process {
            if (-not $_.href) { return }

            $fileName = [System.IO.Path]::GetFileName($_.href)

            if ($fileName -notmatch '^php_xdebug-.*\.dll$') { return }

            if ($fileName -notmatch "php_xdebug-[\d\.a-zA-Z]+-$version-") { return }

            $xDebugVersion = '2.0'
            if ($fileName -match 'php_xdebug-([^-]+)') {
                $xDebugVersion = $matches[1]
            }

            $formattedList += @{
                href          = "$($PVMConfig.links.xdebugBase)$($_.href)"
                version       = $version
                extVersion    = $xDebugVersion;
                arch          = if ($fileName -match '(x86_64|x64)(?=\.dll$)') { 'x64' } else { 'x86' }
                buildType     = if ($fileName -match '(?i)(?:^|-)nts(?:-|\.dll$)') { 'NTS' } else { 'TS' }
                compiler      = if ($fileName -match '(?i)\b(vs|vc)\d+\b') { $matches[0].ToUpper() } else { 'unknown' }
                fileName      = $fileName
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

function Install-XDebugExtension {
    param ($iniPath, $skipConfirmation = $false)

    try {
        $currentVersionObj = Get-CurrentPHPVersion
        $currentVersion = $currentVersionObj.version -replace '^(\d+\.\d+)\..*$', '$1'
        $xDebugList = Get-OrUpdateCache -cacheFileName "packages_links_for_xdebug_php_$($currentVersion)_xdebug" -compute {
            return Show-SpinnerWhileJob -argumentList @($currentVersion) -scriptBlock {
                param ($currentVersion)

                $data = Get-XDebugFromUrl -url $PVMConfig.links.xdebugHistorical -version $currentVersion
                return @{ pvmData = $data }
            } -rethrow $true
        }

        if ($null -eq $xDebugList -or $xDebugList.Count -eq 0) {
            Show-Error -message "`nNo match was found, check the '$($PVMConfig.paths.logError)' for any potentiel errors"
            return -1
        }

        $xDebugList = $xDebugList | Where-Object -FilterScript {
            if ($null -ne $currentVersionObj.arch) {
                if ($_.arch -ne $currentVersionObj.arch) { return $false }
            }

            if ($null -ne $currentVersionObj.buildType) {
                if ($_.buildType -ne $currentVersionObj.buildType) { return $false }
            }

            return $true
        }

        Show-Info -message "`nThis is a partial list. For a complete list, visit: $($PVMConfig.links.xdebugHistorical)"
        $chosenItem = Select-ExtensionPackageLink -extName 'Xdebug' -extensionLinks $xDebugList

        if (-not $chosenItem) {
            Show-Error -message "`nYou chose the wrong index"
            return -1
        }

        $null = Invoke-WebRequestWrapper -uri $chosenItem.href -outFile $PVMConfig.paths.php
        $phpPath = Split-Path -Path $iniPath -Parent

        if (-not $skipConfirmation) {
            if (Test-FileExists -path "$phpPath\ext\$($chosenItem.fileName)") {
                $response = Read-HostWrapper -prompt "`n$($chosenItem.fileName) already exists. Would you like to overwrite it? (y/n)"
                if (Test-NoResponse -response $response) {
                    Remove-ItemWrapper -path "$($PVMConfig.paths.php)\$($chosenItem.fileName)"
                    Write-Gray -message "`nInstallation cancelled"
                    return -1
                }
            }
        }

        Move-ItemWrapper -path "$($PVMConfig.paths.php)\$($chosenItem.fileName)" -destination "$phpPath\ext"
        $xDebugConfig = Get-XdebugConfigV2 -XDebugPath $($chosenItem.fileName)
        if ($chosenItem.extVersion -like '3.*') {
            $xDebugConfig = Get-XdebugConfigV3 -XDebugPath $($chosenItem.fileName)
        }

        $code = Add-MissingPHPExtensionToIni -iniPath $iniPath -extFileName $chosenItem.fileName -enable $false
        if ($code -ne 0) {
            Show-Error -message "`nFailed to add XDebug"
            return -1
        } else {
            $iniContent = Get-ContentWrapper -path $iniPath
            if ($iniContent -notcontains '[xdebug]') {
                $xDebugConfig = "`n$($xDebugConfig -join "`n")"
                Add-ContentWrapper -path $iniPath -value $xDebugConfig
            }
        }

        Show-Success -message "`nXDebug installed successfully"

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to install extension 'xdebug'"; exception = $_ }
        return -1
    }
}

function Add-MissingPHPExtensionToIni {
    param ($iniPath, $extFileName, $enable = $true)

    try {
        if (Test-FileNotExists -path $iniPath) {
            Show-Error -message "`nphp.ini file not found: $iniPath"
            return -1
        }

        $null = Backup-IniFile -iniPath $iniPath

        $phpDirectory = Split-Path -Path $iniPath -Parent
        $extDirectory = "$phpDirectory\ext"

        if (Test-DirectoryNotExists -path $extDirectory) {
            Show-Error -message "`nExtensions directory not found: $extDirectory"
            return -1
        }

        if (Test-FileNotExists -path "$extDirectory\$extFileName") {
            Show-Error -message "`nExtension file not found: $extFileName"
            return -1
        }

        $matchesList = Get-MatchingPHPExtensionsStatus -iniPath $iniPath -extName $extFileName -includeIniOnly $true
        if ($matchesList.Length -gt 0) {
            Show-Warning -message "- Extension '$extFileName' already exists in php.ini"
            return 0
        }

        $lines = Get-ContentWrapper -path $iniPath
        $commented = if ($enable) { '' } else { ';' }
        $isZendExtension = Get-ZendExtensionsList | Where-Object -FilterScript { $extFileName -like "*$_*" }
        if ($isZendExtension) {
            $lines += "`n$commented" + "zend_extension=$extFileName"
        } else {
            $lines += "`n$commented" + "extension=$extFileName"
        }
        Set-ContentWrapper -path $iniPath -value $lines
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
        $currentVersionObj = Get-CurrentPHPVersion
        $currentVersion = $currentVersionObj.version -replace '^(\d+\.\d+)\..*$', '$1'
        $extensionLinksObj = Get-ExtensionFromURL -extName $extName -version $currentVersion

        if (($null -eq $extensionLinksObj) -or ($extensionLinksObj.Count -eq 0) -or ($null -eq $extensionLinksObj.data) -or ($extensionLinksObj.data.Count -eq 0)) {
            $extName = if ($extensionLinksObj) { $extensionLinksObj.extName } else { $extName }
            Show-Error -message "`nNo packages found for $extName"
            return -1
        }

        $extensionLinks = $extensionLinksObj.data | Where-Object -FilterScript {
            if ($null -ne $currentVersionObj.arch) {
                if ($_.arch -ne $currentVersionObj.arch) { return $false }
            }

            if ($null -ne $currentVersionObj.buildType) {
                if ($_.buildType -ne $currentVersionObj.buildType) { return $false }
            }

            return $true
        }

        if ($null -eq $extensionLinks -or $extensionLinks.Count -eq 0) {
            Show-Error -message "`nNo packages found for '$extName' matching current PHP architecture/build type"
            return -1
        }

        $extName = $extensionLinksObj.extName
        if ($extensionLinks.Length -eq 1) {
            $chosenItem = $($extensionLinks)
        } else {
            Show-Info -message "`nThis is a partial list. For a complete list, visit: $($PVMConfig.links.peclPackageRoot)/$extName"
            $chosenItem = Select-ExtensionPackageLink -extName $extName -extensionLinks $extensionLinks
        }

        if (-not $chosenItem) {
            Show-Error -message "`nYou chose the wrong index"
            return -1
        }

        $null = Invoke-WebRequestWrapper -uri $chosenItem.href -outFile $PVMConfig.paths.php
        $fileNamePath = $chosenItem.fileName -replace '.zip$', ''
        $extractPath = "$($PVMConfig.paths.php)\$fileNamePath"
        Expand-Zip -zipPath "$extractPath.zip" -extractPath $extractPath -deleteZipAfter $true
        $files = Get-ChildItemWrapper -path $extractPath
        $extFile = $files | Where-Object -FilterScript {
            ($_.Name -match "^php_$extName.*\.dll$")
        }
        if (-not $extFile) {
            Show-Error -message "`nFailed to find $extName"
            return -1
        }

        $phpPath = Split-Path -Path $iniPath -Parent

        if (-not $skipConfirmation) {
            if (Test-FileExists -path "$phpPath\ext\$($extFile.Name)") {
                $response = Read-HostWrapper -prompt "`n$($extFile.Name) already exists. Would you like to overwrite it? (y/n)"
                if (Test-NoResponse -response $response) {
                    Remove-ItemWrapper -path "$($PVMConfig.paths.php)\$fileNamePath"
                    Write-Gray -message "`nInstallation cancelled"
                    return -1
                }
            }
        }

        Move-ItemWrapper -path $extFile.FullName -destination "$phpPath\ext"
        Remove-ItemWrapper -path $extractPath
        $code = Add-MissingPHPExtensionToIni -iniPath $iniPath -extFileName $extFile.Name -enable $false
        if ($code -ne 0) {
            Show-Error -message "`nFailed to add $extName"
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
                $overallCode = Install-XDebugExtension -iniPath $iniPath -skipConfirmation $skipConfirmation
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
