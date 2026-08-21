
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

function Select-ExtensionLinksFromURL {
    param ($extName)

    $html = Invoke-WebRequestWrapper -uri "$($PVMConfig.links.peclPackageRoot)/$extName"
    $links = $html.Links | Where-Object -FilterScript {
        $_.href -match "/package/$extName/([^/]+)/windows$"
    }

    return $links
}

function Get-PackagesFromSourceLinks {
    param ($extName, $version, $links)

    $formattedList = [System.Collections.Generic.List[object]]::new()
    $links | ForEach-Object -Process {
        try {
            $extVersion = $_.href -replace "/package/$extName/", '' -replace '/windows', ''
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

    $sorted = $linksMatchingExtName | Sort-Object -Property source, extName, extCategory

    $maxNameLength = ($sorted.extName | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
    $sorted | ForEach-Object -Process {
        $extItem = "$($_.extName) ".PadRight($maxNameLength, '.')
        $source = $_.source
        Show-Message -message "[$index] $extItem $source"
        $index++
    }

    do {
        $choiceRaw = Read-HostWrapper -prompt "`nInsert the [number] you want to install"
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

function Get-ExtensionLinksFromURL {
    param ($extName, $version)

    try {
        $links = Get-OrUpdateCache -cacheFileName "available_$($extName)_versions_pecl" -compute {
            return Select-ExtensionLinksFromURL -extName $extName
        }
    } catch {
        Show-Message -message "`nDirect link for extension '$extName' not found, Loading matching extensions..."

        $linksMatchingExtName = Get-ExtensionMatchingCategories -extName $extName

        if ($linksMatchingExtName.Length -eq 0) {
            Show-Error -Message "`nExtension '$extName' not found"
            return $null
        }

        $chosenItem = Select-ExtensionFromMatches -linksMatchingExtName $linksMatchingExtName

        if (-not $chosenItem) { return $null }

        $extName = $chosenItem.extName
        Show-Message -message "`nLoading links for '$extName'..."
        $links = Get-OrUpdateCache -cacheFileName "available_$($extName)_versions_pecl" -compute {
            return Select-ExtensionLinksFromURL -extName $extName
        }
    }

    return @{
        extName = $extName
        links   = $links
    }
}

function Get-ExtensionFromURL {
    param ($extName, $version)

    $linksObj = Get-ExtensionLinksFromURL -extName $extName -version $version

    if (($null -eq $linksObj) -or ($linksObj.Count -eq 0) -or ($null -eq $linksObj.links) -or ($linksObj.links.Count -eq 0)) {
        $extName = if ($linksObj -and $linksObj.extName) { $linksObj.extName } else { $extName }
        return @{ extName = $extName; data = $null }
    }

    $formattedList = Get-OrUpdateCache -cacheFileName "packages_links_for_$($linksObj.extName)_php_$version" -compute {
        return Show-SpinnerWhileJob -argumentList @($linksObj, $version) -scriptBlock {
            param ($linksObj, $version)

            $data = Get-PackagesFromSourceLinks -extName $linksObj.extName -version $version -links $linksObj.links
            return @{ pvmData = $data }
        } -rethrow $true
    }

    return @{
        extName = $linksObj.extName
        data    = $formattedList
    }
}
