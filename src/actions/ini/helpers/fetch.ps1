
function Get-Extension-Matching-Categories-By-Page {
    param ($extName, $link, $page = 1)

    $html = Invoke-WebRequest -Uri "$PECL_BASE_URL/$($link.TrimStart('/'))&pageID=$page"
    $hasMore = $false
    $resultLinks = $html.Links | Where-Object {
        if (-not $_.href) { return $false }
        if ($_.href -match '^/packages\.php\?catpid=\d+&amp;catname=[A-Za-z+]+&pageID=(\d+)$') {
            $hasMore = ($page -eq ($matches[1] - 1))
            return $false
        }

        return ($_.href -like "/package/*$extName*")
    }

    return @{
        hasMore = $hasMore
        resultLinks = $resultLinks
    }
}

function Filter-Extension-Links-From-URL {
    param ($extName)

    $html = Invoke-WebRequest -Uri "$PECL_PACKAGE_ROOT_URL/$extName"
    $links = $html.Links | Where-Object {
        $_.href -match "/package/$extName/([^/]+)/windows$"
    }

    return $links
}

function Get-Packages-From-Source-Links {
    param ($extName, $version, $links)

    $formattedList = @()
    $links | ForEach-Object {
        try {
            $extVersion = $_.href -replace "/package/$extName/", '' -replace '/windows', ''
            $html = Invoke-WebRequest -Uri "$PECL_PACKAGE_ROOT_URL/$extName/$extVersion/windows"
            $html.Links | ForEach-Object {
                if (-not $_.href) { return }

                $fileName = [System.IO.Path]::GetFileName($_.href)

                if ($fileName -notmatch "^php_$extName-.*\.zip$") { return }

                # if ($fileName -notmatch "php_$extName-$version-") { return }
                if ($fileName -notmatch "^php_$extName-[\d\.]+(?:[a-z]+\d+)?-$version-") { return }

                $formattedList += @{
                    href        = $_.href
                    version     = $version
                    extVersion  = $extVersion
                    arch        = if ($fileName -match '(x86_64|x64)(?=\.zip$)') { 'x64' } else { 'x86' }
                    buildType   = if ($fileName -match '(?i)(?:^|-)nts(?:-|\.zip$)') { 'NTS' } else { 'TS' }
                    compiler    = if ($fileName -match '(?i)\b(vs|vc)\d+\b') { $matches[0].ToUpper() } else { 'unknown' }
                    fileName    = $fileName
                }
            }
        } catch {
            $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to find packages for $extName v$extVersion"; exception = $_ }
        }
    }

    return $formattedList
}

function Get-Extension-Matching-Categories {
    param ($extName)

    $html_cat = Invoke-WebRequest -Uri $PECL_PACKAGES_URL
    $linksMatchingExtName = @()
    $null = $html_cat.Links | Where-Object {
        if (-not $_.href) { return $false }

        if ($_.href -notmatch '^/packages\.php\?catpid=\d+&amp;catname=([A-Za-z+]+)$') {
            return $false
        }

        $page = 1
        $category = $matches[1] -replace '\+', ' '
        Write-Host -Object "- Checking category '$category'..." -ForegroundColor Gray
        do {
            $hasMore = $false
            $result = Get-Extension-Matching-Categories-By-Page -extName $extName -link $_.href -page $page
            $hasMore = $result.hasMore
            $page++

            if ($result.resultLinks.Count -gt 0) {
                $linksMatchingExtName += $result.resultLinks
            }
        } while ($hasMore)

        return $false
    }

    return $linksMatchingExtName
}

function Get-Extension-Links-From-URL {
    param ($extName, $version)

    try {
        $links = Get-OrUpdateCache -cacheFileName "available_$($extName)_versions_$version" -compute {
            Filter-Extension-Links-From-URL -extName $extName
        }
    } catch {
        Write-Host -Object "`nExtension '$extName' not found, Loading matching extensions..."

        $linksMatchingExtName = Get-Extension-Matching-Categories -extName $extName

        if ($linksMatchingExtName.Count -eq 0) {
            Write-Host -Object "`nExtension '$extName' not found" -ForegroundColor DarkYellow
            return $null
        }

        if ($linksMatchingExtName.Count -eq 1) {
            $chosenItem = $($linksMatchingExtName)
        } else {
            Write-Host -Object "`nMatching '$extName' extension:"
            $index = 0
            $linksMatchingExtName | ForEach-Object {
                $extItem = $_.href -replace '/package/', ''
                Write-Host -Object "[$index] $extItem"
                $index++
            }

            do {
                $choiceRaw = Read-Host -Prompt "`nInsert the [number] you want to install"
                $choiceRaw = $choiceRaw.Trim()
                if ([string]::IsNullOrWhiteSpace($choiceRaw)) {
                    Write-Host -Object "`nInstallation cancelled"
                    return $null
                }

                $choice = $null
                if (-not [int]::TryParse($choiceRaw, [ref]$choice)) {
                    Write-Host -Object 'Please enter a valid positive number.' -ForegroundColor Yellow
                    continue
                }

                if ($choice -lt 0 -or $choice -gt $linksMatchingExtName.Length - 1) {
                    Write-Host -Object "Number must be between 0 and $($linksMatchingExtName.Length - 1)." -ForegroundColor Yellow
                    continue
                }

                break
            } while ($true)

            $chosenItem = $linksMatchingExtName[$choice]
            if (-not $chosenItem) {
                Write-Host -Object "`nYou chose the wrong index: $choice" -ForegroundColor DarkYellow
                return $null
            }
        }

        $extName = $chosenItem.href -replace '/package/', ''
        $links = Get-OrUpdateCache -cacheFileName "available_$($extName)_versions_$version" -compute {
            Filter-Extension-Links-From-URL -extName $extName
        }
    }

    return @{
        extName = $extName
        links = $links
    }
}

function Get-Extension-From-URL {
    param ($extName, $version)

    $linksObj = Get-Extension-Links-From-URL -extName $extName -version $version

    if (($null -eq $linksObj) -or ($linksObj.Count -eq 0) -or ($null -eq $linksObj.links) -or ($linksObj.links.Count -eq 0)) {
        $extName = if ($linksObj -and $linksObj.extName) { $linksObj.extName } else { $extName }
        Write-Host -Object "`nNo versions found for $extName" -ForegroundColor DarkYellow
        return @{ extName = $extName; data = $null }
    }

    $formattedList = Get-OrUpdateCache -cacheFileName "packages_links_for_$($linksObj.extName)_php_$version" -compute {
        Get-Packages-From-Source-Links -extName $linksObj.extName -version $version -links $linksObj.links
    }

    return @{
        extName = $linksObj.extName
        data = $formattedList
    }
}
