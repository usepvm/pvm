
function Get-ExtensionCategoriesByPage {
    param ($extCategory, $link, $page = 1)

    $availableExtensions = @()
    $html = Get-WebResponse -uri "$($PVMConfig.links.peclBase)/$($link.TrimStart('/'))&pageID=$page"
    $hasMore = $false
    $null = $html.Links | Where-Object {
        if (-not $_.href) { return $false }
        if ($_.href -match '^/packages\.php\?catpid=\d+&amp;catname=[A-Za-z+]+&pageID=(\d+)$') {
            $hasMore = ($page -eq ($matches[1] - 1))
            return $false
        }
        if ($_.href -notmatch '^/package/[A-Za-z0-9_]+$') {
            return $false
        }

        $null = $_.outerHTML -match '(?s)<strong>(?<package>.*?)</strong>.*?<td[^>]*>(?<description>.*?)</td>'
        $description = $matches['description']

        $extName = ($_.href -replace '/package/', '').Trim()
        $_ | Add-Member -NotePropertyName 'extName' -NotePropertyValue $extName -Force
        $_ | Add-Member -NotePropertyName 'extCategory' -NotePropertyValue $extCategory -Force
        $_ | Add-Member -NotePropertyName 'description' -NotePropertyValue $description -Force

        $availableExtensions += $_
        return $true
    }

    return @{
        hasMore             = $hasMore
        availableExtensions = $availableExtensions
    }
}

function Get-PHPExtensionsFromSource {
    $availableExtensions = @{}
    try {
        $html_cat = Get-WebResponse -uri $PVMConfig.links.peclPackages
        $null = $html_cat.Links | Where-Object {
            if (-not $_.href) { return $false }

            $href = $_.href
            if ($href -notmatch '^/packages\.php\?catpid=\d+&amp;catname=([A-Za-z+]+)$') {
                return $false
            }

            $extCategory = $matches[1] -replace '\+', ' '

            $availableExtensions = Show-SpinnerWhileJob -argumentList @($availableExtensions, $extCategory, $href) -scriptBlock {
                param ($availableExtensions, $extCategory, $href)

                $page = 1
                do {
                    $hasMore = $false
                    $result = Get-ExtensionCategoriesByPage -extCategory $extCategory -link $href -page $page
                    $availableExtensions[$extCategory] += $result.availableExtensions
                    $hasMore = $result.hasMore
                    $page++
                } while ($hasMore)

                if ($availableExtensions[$extCategory].Count -eq 0) {
                    $availableExtensions.Remove($extCategory)
                }

                return @{ pvmData = $availableExtensions }
            } -message @{ content = "- Loading category '$extCategory'..."; color = 'Cyan' } -rethrow $true

            return $true
        }
        $availableExtensions['XDebug'] = @(
            @{
                href        = $PVMConfig.links.xdebugHistorical
                extName     = 'xdebug'
                extCategory = 'XDebug'
            }
        )
        $availableExtensionsOrdered = [ordered] @{}
        $availableExtensions.GetEnumerator() | Sort-Object Key | ForEach-Object { $availableExtensionsOrdered[$_.Key] = $_.Value }

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
    $availableExtensions.PSObject.Properties | ForEach-Object {
        $categoryMatches = $_.Name -like "*$term*"
        $searchResult = if ($term -and -not $categoryMatches) {
            $_.Value | Where-Object {
                ($_.extName -like "*$term*" -or $_.description -like "*$term*")
            }
        } else {
            $_.Value
        }
        if ($searchResult.Length -gt 0) {
            $result[$_.Name] = @($searchResult)
        }
    }
    return $result
}

function Select-ExtensionLinksFromURL {
    param ($extName)

    $html = Get-WebResponse -uri "$($PVMConfig.links.peclPackageRoot)/$extName"
    $links = $html.Links | Where-Object {
        $_.href -match "/package/$extName/([^/]+)/windows$"
    }

    return $links
}

function Get-PackagesFromSourceLinks {
    param ($extName, $version, $links)

    $formattedList = @()
    $links | ForEach-Object {
        try {
            $extVersion = $_.href -replace "/package/$extName/", '' -replace '/windows', ''
            $html = Get-WebResponse -uri "$($PVMConfig.links.peclPackageRoot)/$extName/$extVersion/windows"
            $html.Links | ForEach-Object {
                if (-not $_.href) { return }

                $fileName = [System.IO.Path]::GetFileName($_.href)

                if ($fileName -notmatch "^php_$extName-.*\.zip$") { return }

                # if ($fileName -notmatch "php_$extName-$version-") { return }
                if ($fileName -notmatch "^php_$extName-[\d\.]+(?:[a-z]+\d+)?-$version-") { return }

                $formattedList += @{
                    href       = $_.href
                    version    = $version
                    extVersion = $extVersion
                    arch       = if ($fileName -match '(x86_64|x64)(?=\.zip$)') { 'x64' } else { 'x86' }
                    buildType  = if ($fileName -match '(?i)(?:^|-)nts(?:-|\.zip$)') { 'NTS' } else { 'TS' }
                    compiler   = if ($fileName -match '(?i)\b(vs|vc)\d+\b') { $matches[0].ToUpper() } else { 'unknown' }
                    fileName   = $fileName
                }
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
    $linksMatchingExtName = $grouped.Values | ForEach-Object { $_ }

    return $linksMatchingExtName
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

        if ($linksMatchingExtName.Length -eq 1) {
            $chosenItem = $($linksMatchingExtName)
            $extName = $chosenItem.extName
            Show-Message -message "`nMatching found : '$extName'"
        } else {
            Show-Info -message "`nMatching '$extName' extension:"
            $index = 0
            $linksMatchingExtName | Sort-Object extName | ForEach-Object {
                $extItem = $_.extName
                Show-Message -message "[$index] $extItem"
                $index++
            }

            do {
                $choiceRaw = Read-Host-Wrapper -prompt "`nInsert the [number] you want to install"
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

                break
            } while ($true)

            $chosenItem = $linksMatchingExtName[$choice]
            if (-not $chosenItem) {
                Show-Error -Message "`nYou chose the wrong index: $choice"
                return $null
            }
        }

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
