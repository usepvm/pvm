
function Get-ExtensionHandlers {
    return @{
        SourceHandlers = @{
            'xdebug.org' = @{
                GetPackages = {
                    param ($version)
                    return Get-OrUpdateCache -cacheFileName "packages_links_for_xdebug_php_$($version)_xdebug" -compute {
                        return Show-SpinnerWhileJob -argumentList @($version) -scriptBlock {
                            param ($version)
                            $data = Get-XDebugFromUrl -url $PVMConfig.links.xdebugHistorical -version $version
                            return @{ pvmData = $data }
                        } -rethrow $true
                    }
                }
                Download = {
                    param ($chosenItem, $phpPath, $skipConfirmation)

                    try {
                        $null = Invoke-WebRequestWrapper -uri $chosenItem.href -outFile $PVMConfig.paths.directories.php
                        $extFile = @{
                            Name = $chosenItem.fileName
                            FullName = "$($PVMConfig.paths.directories.php)\$($chosenItem.fileName)"
                        }

                        if (-not $skipConfirmation) {
                            if (Test-FileExists -path "$phpPath\ext\$($extFile.Name)") {
                                $response = Read-HostWrapper -prompt "`n$($extFile.Name) already exists. Would you like to overwrite it? (y/n)"
                                if (Test-NoResponse -response $response) {
                                    Remove-ItemWrapper -path $extFile.FullName
                                    Write-Gray -message "`nInstallation cancelled"
                                    return $null
                                }
                            }
                        }

                        Move-ItemWrapper -path $extFile.FullName -destination "$phpPath\ext"
                        return $extFile
                    } catch {
                        $null = Add-LogEntry -data @{ header = "Xdebug.org Handler - Failed to download extension"; exception = $_ }
                        return $null
                    }
                }
                MoreInfoUrl = $PVMConfig.links.xdebugHistorical
            }
            'pecl.php.net' = @{
                GetPackages = {
                    param ($version, $linksObj)
                    if (($null -eq $linksObj.links) -or ($linksObj.links.Count -eq 0)) {
                        return $null
                    }
                    return Get-OrUpdateCache -cacheFileName "packages_links_for_$($linksObj.extName)_php_$($version)_pecl" -compute {
                        return Show-SpinnerWhileJob -argumentList @($linksObj, $version) -scriptBlock {
                            param ($linksObj, $version)
                            $data = Get-PackagesFromSourceLinks -extName $linksObj.extName -version $version -links $linksObj.links
                            return @{ pvmData = $data }
                        } -rethrow $true
                    }
                }
                Download = {
                    param ($chosenItem, $phpPath, $skipConfirmation, $extName)

                    try {
                        $null = Invoke-WebRequestWrapper -uri $chosenItem.href -outFile $PVMConfig.paths.directories.php
                        $fileNamePath = $chosenItem.fileName -replace '.zip$', ''
                        $extractPath = "$($PVMConfig.paths.directories.php)\$fileNamePath"
                        Expand-Zip -zipPath "$extractPath.zip" -extractPath $extractPath -deleteZipAfter $true
                        $files = Get-ChildItemWrapper -path $extractPath
                        $extFile = $files | Where-Object -FilterScript {
                            ($_.Name -match "^php_$extName.*\.dll$")
                        }

                        if (-not $extFile) {
                            Remove-ItemWrapper -path $extractPath
                            return $null
                        }

                        if (-not $skipConfirmation) {
                            if (Test-FileExists -path "$phpPath\ext\$($extFile.Name)") {
                                $response = Read-HostWrapper -prompt "`n$($extFile.Name) already exists. Would you like to overwrite it? (y/n)"
                                if (Test-NoResponse -response $response) {
                                    Remove-ItemWrapper -path $extractPath
                                    Write-Gray -message "`nInstallation cancelled"
                                    return $null
                                }
                            }
                        }

                        Move-ItemWrapper -path $extFile.FullName -destination "$phpPath\ext"
                        Remove-ItemWrapper -path $extractPath
                        return $extFile
                    } catch {
                        $null = Add-LogEntry -data @{ header = "PECL Handler - Failed to download extension"; exception = $_ }
                        return $null
                    }
                }
                MoreInfoUrl = {
                    param ($extName)
                    return "$($PVMConfig.links.peclPackageRoot)/$extName"
                }
            }
        }
        ExtensionConfigHandlers = @{
            'xdebug' = {
                param ($iniPath, $fileName, $extVersion)

                try {
                    $xDebugConfig = Get-XdebugConfigV2 -XDebugPath $fileName
                    if ($extVersion -like '3.*') {
                        $xDebugConfig = Get-XdebugConfigV3 -XDebugPath $fileName
                    }

                    $iniContent = Get-ContentWrapper -path $iniPath
                    if ($iniContent -notcontains '[xdebug]') {
                        $xDebugConfig = "`n$($xDebugConfig -join "`n")"
                        Add-ContentWrapper -path $iniPath -value $xDebugConfig
                    }

                    return 0
                } catch {
                    $null = Add-LogEntry -data @{ header = "Xdebug Config Handler - Failed to apply configuration"; exception = $_ }
                    return -1
                }
            }
            'default' = {
                param ($iniPath, $fileName, $extVersion)

                return (Add-MissingPHPExtensionToIni -iniPath $iniPath -extFileName $extFile.Name -enable $false)
            }
        }
    }
}

function Get-SourceHandler {
    param ($sourceUrl)

    $handlers = Get-ExtensionHandlers
    $sourceHandlers = $handlers.SourceHandlers

    if ($sourceHandlers.ContainsKey($sourceUrl)) {
        return $sourceHandlers[$sourceUrl]
    }

    # Default to PECL handler for unknown sources
    return $sourceHandlers['pecl.php.net']
}

function Get-ExtensionConfigHandler {
    param ($extName)

    $handlers = Get-ExtensionHandlers
    $configHandlers = $handlers.ExtensionConfigHandlers

    $baseExtName = ConvertTo-ExtensionId -name $extName

    if ($configHandlers.ContainsKey($baseExtName)) {
        return $configHandlers[$baseExtName]
    }

    # Default handler - no special configuration needed
    return $configHandlers['default']
}

function Get-XDebugFromUrl {
    param ($url, $version)

    try {
        $html = Invoke-WebRequestWrapper -uri $url
        $links = $html.Links

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

function Get-ExtensionCategoriesByPage {
    param ($extCategory, $link, $page = 1)

    $availableExtensions = [System.Collections.Generic.List[object]]::new()
    $html = Invoke-WebRequestWrapper -uri "$($PVMConfig.links.peclBase)/$($link.TrimStart('/'))&pageID=$page"
    $hasMore = $false
    $html.Links | ForEach-Object -Process {
        if (-not $_.href) { return }
        if ($_.href -match '^/packages\.php\?catpid=\d+&amp;catname=[A-Za-z+]+&pageID=(\d+)$') {
            $hasMore = ($page -eq ($matches[1] - 1))
            return
        }
        if ($_.href -notmatch '^/package/[A-Za-z0-9_]+$') {
            return
        }

        $null = $_.outerHTML -match '(?s)<strong>(?<package>.*?)</strong>.*?<td[^>]*>(?<description>.*?)</td>'
        $description = $matches['description']

        $availableExtensions.Add(@{
            extName     = ($_.href -replace '/package/', '').Trim()
            description = $description
            href        = "$($PVMConfig.links.peclBase)$($_.href)"
            extCategory = $extCategory
            source      = (Get-BaseUrl -url $PVMConfig.links.peclBase)
        })
    }

    return @{
        hasMore             = $hasMore
        availableExtensions = $availableExtensions
    }
}

function Get-PHPExtensionsFromSource {
    $availableExtensions = @{}
    try {
        $html_cat = Invoke-WebRequestWrapper -uri $PVMConfig.links.peclPackages
        $null = $html_cat.Links | Where-Object -FilterScript {
            if (-not $_.href) { return $false }

            $href = $_.href
            if ($href -notmatch '^/packages\.php\?catpid=\d+&amp;catname=([A-Za-z+]+)$') {
                return $false
            }

            $extCategory = $matches[1] -replace '\+', ' '

            $availableExtensions = Show-SpinnerWhileJob -argumentList @($availableExtensions, $extCategory, $href) -scriptBlock {
                param ($availableExtensions, $extCategory, $href)

                $currentCategoryResult = [System.Collections.Generic.List[object]]::new()
                $page = 1
                do {
                    $hasMore = $false
                    $result = Get-ExtensionCategoriesByPage -extCategory $extCategory -link $href -page $page
                    $currentCategoryResult.AddRange($result.availableExtensions)
                    $hasMore = $result.hasMore
                    $page++
                } while ($hasMore)

                if ($currentCategoryResult.Count -gt 0) {
                    $availableExtensions[$extCategory] = $currentCategoryResult
                }

                return @{ pvmData = $availableExtensions }
            } -message @{ content = "  Loading category '$extCategory'..."; color = 'Cyan' } -rethrow $true

            return $true
        }
        $availableExtensions['XDebug'] = @(
            @{
                href        = $PVMConfig.links.xdebugHistorical
                extName     = 'xdebug'
                extCategory = 'XDebug'
                description = 'Xdebug is a debugging and productivity extension for PHP'
                source      = (Get-BaseUrl -url $PVMConfig.links.xdebugBase)
            }
        )
        $availableExtensionsOrdered = [ordered] @{}
        $availableExtensions.GetEnumerator() | Sort-Object -Property Key | ForEach-Object -Process { $availableExtensionsOrdered[$_.Key] = $_.Value }

        return $availableExtensionsOrdered
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get PHP extensions from source"; exception = $_ }
        return @{}
    }
}

function Get-AvailablePHPExtensions {
    return Get-OrUpdateCache -cacheFileName 'available_extensions' -compute {
        return [pscustomobject] (Get-PHPExtensionsFromSource)
    }
}

function Get-FilteredPHPExtensionsByCategory {
    param ($availableExtensions, $term = $null)

    $result = @{}
    $availableExtensions.PSObject.Properties | ForEach-Object -Process {
        $categoryMatches = $_.Name -like "*$term*"
        if ($term -and -not $categoryMatches) {
            $searchResult = $_.Value | Where-Object -FilterScript {
                return ($_.extName -like "*$term*" -or $_.description -like "*$term*")
            }
        } else {
            $searchResult = $_.Value
        }
        $searchResult = @($searchResult)
        if ($searchResult.Length -gt 0) {
            $result[$_.Name] = @($searchResult)
        }
    }
    return $result
}

function Get-ExtensionAvailableReleasesLinks {
    param ($extName)

    $html = Invoke-WebRequestWrapper -uri "$($PVMConfig.links.peclPackageRoot)/$extName"
    $links = [System.Collections.Generic.List[object]]::new()
    $null = $html.Links | Foreach-Object -Process {
        if ($_.href -match "/package/$extName/([^/]+)/windows$") {
            $links.Add(@{ href = "$($PVMConfig.links.peclBase)$($_.href)" })
        }
    }

    return $links
}

function Get-PackagesFromSourceLinks {
    param ($extName, $version, $links)

    $formattedList = [System.Collections.Generic.List[object]]::new()
    $links | ForEach-Object -Process {
        try {
            $extVersion = $_.href -replace "$($PVMConfig.links.peclBase)/package/$extName/", '' -replace '/windows', ''
            $html = Invoke-WebRequestWrapper -uri "$($PVMConfig.links.peclPackageRoot)/$extName/$extVersion/windows"
            $html.Links | ForEach-Object -Process {
                if (-not $_.href) { return }

                $fileName = [System.IO.Path]::GetFileName($_.href)

                if ($fileName -notmatch "^php_$extName-.*\.zip$") { return }

                # if ($fileName -notmatch "php_$extName-$version-") { return }
                if ($fileName -notmatch "^php_$extName-[\d\.]+(?:[a-z]+\d+)?-$version-") { return }

                $formattedList.Add(@{
                    href       = $_.href
                    version    = $version
                    extVersion = $extVersion
                    arch       = if ($fileName -match '(x86_64|x64)(?=\.zip$)') { 'x64' } else { 'x86' }
                    buildType  = if ($fileName -match '(?i)(?:^|-)nts(?:-|\.zip$)') { 'NTS' } else { 'TS' }
                    compiler   = if ($fileName -match '(?i)\b(vs|vc)\d+\b') { $matches[0].ToUpper() } else { 'unknown' }
                    fileName   = $fileName
                })
            }
        } catch {
            $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to find packages for $extName v$extVersion"; exception = $_ }
        }
    }

    return $formattedList
}

function Get-ExtensionMatchingCategories {
    param ($extName)

    $availableExtensions = Get-AvailablePHPExtensions

    if ($availableExtensions.Count -eq 0) {
        Show-Error -message "`nNo extensions found"
        return @()
    }

    $grouped = Get-FilteredPHPExtensionsByCategory -availableExtensions $availableExtensions -term $extName
    $linksMatchingExtName = $grouped.Values | ForEach-Object -Process { $_ }

    return $linksMatchingExtName
}

function Select-ExtensionFromMatches {
    param ($linksMatchingExtName)

    if ($null -eq $linksMatchingExtName -or $linksMatchingExtName.Length -eq 0) {
        return $null
    }

    if ($linksMatchingExtName.Length -eq 1) {
        $chosenItem = $($linksMatchingExtName)
        $extName = $chosenItem.extName
        Show-Message -message "`nMatching found : '$extName'"
        return $chosenItem
    }

    Show-Info -message "`nMatching '$extName' extension:"
    $index = 0

    $sorted = $linksMatchingExtName | Sort-Object -Property @{ Expression = { $_.source } }, @{ Expression = { $_.extName } }, @{ Expression = { $_.extCategory } }

    $maxNameLength = ($sorted.extName | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
    $sorted | ForEach-Object -Process {
        $extItem = "$($_.extName) ".PadRight($maxNameLength, '.')
        $source = $_.source
        Show-Message -message "[$index] $extItem $source"
        $index++
    }

    do {
        $choiceRaw = Read-HostWrapper -prompt "`nEnter the [number] of your selection"
        if ([string]::IsNullOrWhiteSpace($choiceRaw)) {
            Write-Gray -message "`nInstallation cancelled"
            return $null
        }

        $choice = $null
        if (-not [int]::TryParse($choiceRaw, [ref]$choice)) {
            Show-Warning -message 'Please enter a valid positive number.'
            continue
        }

        if ($choice -lt 0 -or $choice -gt $linksMatchingExtName.Length - 1) {
            Show-Warning -message "Number must be between 0 and $($linksMatchingExtName.Length - 1)."
            continue
        }

        return $sorted[$choice]
    } while ($true)
}

function Resolve-ExtensionLinks {
    param ($extName, $version)

    try {
        $links = Get-OrUpdateCache -cacheFileName "available_$($extName)_versions_$($version)_pecl" -compute {
            return Get-ExtensionAvailableReleasesLinks -extName $extName
        }
        $source = 'pecl.php.net'
    } catch {
        Show-Message -message "`nDirect link for extension '$extName' not found, Loading matching extensions..."

        $linksMatchingExtName = Get-ExtensionMatchingCategories -extName $extName

        if ($linksMatchingExtName.Length -eq 0) {
            Show-Error -message "`nExtension '$extName' not found"
            return $null
        }

        $chosenItem = Select-ExtensionFromMatches -linksMatchingExtName $linksMatchingExtName

        if (-not $chosenItem) { return $null }

        $extName = $chosenItem.extName
        $source = $chosenItem.source
        Show-Message -message "`nLoading links for '$extName'..."

        # Only get PECL links if the source is pecl.php.net
        if ($source -eq 'pecl.php.net') {
            $links = Get-OrUpdateCache -cacheFileName "available_$($extName)_versions_$($version)_pecl" -compute {
                return Get-ExtensionAvailableReleasesLinks -extName $extName
            }
        } else {
            $links = @()
        }
    }

    return @{
        extName = $extName
        links   = $links
        source  = $source
    }
}

function Get-ExtensionPackages {
    param ($extName, $version)

    $linksObj = Resolve-ExtensionLinks -extName $extName -version $version

    if ($null -eq $linksObj) {
        return @{ extName = $extName; data = $null; source = 'unknown' }
    }

    $handler = Get-SourceHandler -sourceUrl $linksObj.source
    if (-not $handler) {
        return @{ extName = $linksObj.extName; data = $null; source = $linksObj.source }
    }

    $formattedList = if ($linksObj.source -eq 'pecl.php.net') {
        & $handler.GetPackages -version $version -linksObj $linksObj
    } else {
        & $handler.GetPackages -version $version
    }

    if ($null -eq $formattedList) {
        return @{ extName = $linksObj.extName; data = $null; source = $linksObj.source }
    }

    return @{
        extName = $linksObj.extName
        data    = $formattedList
        source  = $linksObj.source
    }
}
