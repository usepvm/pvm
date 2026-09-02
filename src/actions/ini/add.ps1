
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

    $packageIndex = Read-HostWrapper -prompt "`nEnter the [number] of your selection"
    if ([string]::IsNullOrWhiteSpace($packageIndex)) {
        Write-Gray -message "`nInstallation cancelled"
        return $null
    }

    return ($extensionLinks | Where-Object -FilterScript { $_.index -eq $packageIndex })
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

        $matchesList = (Get-MatchingPHPExtensionsStatus -iniPath $iniPath -extName $extFileName -includeIniOnly $true -addToIniFileIfMissing $false) | Select-Object -First 1
        if ($matchesList.Length -gt 0 -and $matchesList.LineNumber -gt 0) {
            Show-Warning -message "- Extension '$extFileName' already exists in php.ini"
            return 0
        }

        $lines = Get-ContentWrapper -path $iniPath
        $commented = if ($enable) { '' } else { ';' }
        $isZendExtension = [bool](Get-ZendExtensionsList | Where-Object -FilterScript { $extFileName -like "*$_*" } | Select-Object -First 1)
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
        New-Line
        $sourceHandlers = (Get-ExtensionHandlers).SourceHandlers
        $sourceNames = @($sourceHandlers.Keys) | Sort-Object
        $index = 0
        $sourceNames | Foreach-Object -Process {
            Show-Message -message "[$index] $_"
            $index++
        }
        $selectedIndex = Read-HostWrapper -prompt "`nEnter the [number] of your selection"
        if ([string]::IsNullOrWhiteSpace($selectedIndex)) {
            Write-Gray -message "`nInstallation cancelled"
            return -1
        }
        $choice = $null
        if (-not [int]::TryParse($selectedIndex, [ref]$choice)) {
            Show-Warning -message "`nYou answer is invalid!"
            return -1
        }
        if ($choice -lt 0 -or $choice -gt $sourceHandlers.Count - 1) {
            Show-Warning -message "Number must be between 0 and $($sourceHandlers.Count - 1)."
            return -1
        }

        $selectedSource = $sourceNames[$choice]
        $handler = Get-SourceHandler -sourceUrl $selectedSource

        if (-not $handler) {
            Show-Error -message "`nNo handler found for source: $source"
            return -1
        }

        if ($handler.SupportedExtensions -and $handler.SupportedExtensions -notcontains '*') {
            $normalizedExtName = ConvertTo-ExtensionId -name $extName
            if ($handler.SupportedExtensions -notcontains $normalizedExtName) {
                Show-Error -message "`nSource '$selectedSource' does not support extension '$extName'. Supported extensions: $($handler.SupportedExtensions -join ', ')"
                return -1
            }
        }

        $extensionLinksObj = & $handler.ResolveLinks -extName $extName

        if (($null -eq $extensionLinksObj) -or ($extensionLinksObj.Count -eq 0) -or ($null -eq $extensionLinksObj.data) -or ($extensionLinksObj.data.Count -eq 0)) {
            $extName = if ($extensionLinksObj) { $extensionLinksObj.extName } else { $extName }
            Show-Error -message "`nNo packages found for $extName"
            return -1
        }

        $currentVersionObj = Get-CurrentPHPVersion
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
        $source = $extensionLinksObj.source

        if ($extensionLinks.Length -eq 1) {
            $chosenItem = $($extensionLinks)
        } else {
            $moreInfoUrl = if ($handler.MoreInfoUrl -is [scriptblock]) {
                & $handler.MoreInfoUrl $extName
            } else {
                $handler.MoreInfoUrl
            }
            Show-Info -message "`nThis is a partial list. For a complete list, visit: $moreInfoUrl"
            $chosenItem = Select-ExtensionPackageLink -extName $extName -extensionLinks $extensionLinks
        }

        if (-not $chosenItem) {
            Show-Error -message "`nYou chose the wrong index"
            return -1
        }

        $phpPath = Split-Path -Path $iniPath -Parent

        $downloadParams = @{
            chosenItem = $chosenItem
            phpPath = $phpPath
            skipConfirmation = $skipConfirmation
        }
        if ($source -eq 'pecl.php.net') {
            $downloadParams.extName = $extName
        }

        $extFile = & $handler.Download @downloadParams
        if (-not $extFile) {
            Show-Error -message "`nFailed to download $extName"
            return -1
        }

        $configHandler = Get-ExtensionConfigHandler -extName $extFile.Name

        $configCode = & $configHandler -iniPath $iniPath -fileName $extFile.Name -extVersion $chosenItem.extVersion
        if ($configCode -ne 0) {
            Show-Error -message "`nFailed to apply configuration for $extName"
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

        $codes = @()
        foreach ($extName in $extNames) {
            $codes += Install-Extension -iniPath $iniPath -extName $extName -skipConfirmation $skipConfirmation
        }

        if ($codes | Where-Object -FilterScript { $_ -ne 0 }) { return -1 }
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to install '$($extNames -join ', ')'"; exception = $_ }
        return -1
    }
}
