
function Get-Extension-Categories-By-Page {
    param ($extCategory, $link, $page = 1)

    $availableExtensions = @()
    $html = Invoke-WebRequest -Uri "$($PVMConfig.links.peclBase)/$($link.TrimStart('/'))&pageID=$page"
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
        $extName = ($_.href -replace '/package/', '').Trim()
        $_ | Add-Member -NotePropertyName 'extName' -NotePropertyValue $extName -Force
        $_ | Add-Member -NotePropertyName 'extCategory' -NotePropertyValue $extCategory -Force
        $availableExtensions += $_
        return $true
    }

    return @{
        hasMore             = $hasMore
        availableExtensions = $availableExtensions
    }
}

function Get-PHPExtensions-From-Source {
    $availableExtensions = @{}
    try {
        $html_cat = Invoke-WebRequest -Uri $PVMConfig.links.peclPackages
        $null = $html_cat.Links | Where-Object {
            if (-not $_.href) { return $false }

            if ($_.href -notmatch '^/packages\.php\?catpid=\d+&amp;catname=([A-Za-z+]+)$') {
                return $false
            }

            $page = 1
            $extCategory = $matches[1] -replace '\+', ' '
            do {
                $hasMore = $false
                $result = Get-Extension-Categories-By-Page -extCategory $extCategory -link $_.href -page $page
                $availableExtensions[$extCategory] += $result.availableExtensions
                $hasMore = $result.hasMore
                $page++
            } while ($hasMore)

            if ($availableExtensions[$extCategory].Count -eq 0) {
                $availableExtensions.Remove($extCategory)
            }
            return $true
        }
        $availableExtensions['XDebug'] = @(
            @{
                href        = $PVMConfig.links.xdebugHistorical
                extName     = 'xdebug'
                extCategory = 'XDebug'
            }
        )
        $dataToCache = [ordered] @{}
        $availableExtensions.GetEnumerator() | Sort-Object Key | ForEach-Object { $dataToCache[$_.Key] = $_.Value }
        $null = Cache-Data -cacheFileName 'available_extensions' -data $dataToCache -depth 3

        return $availableExtensions
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get PHP extensions from source"; exception = $_ }
        return @{}
    }
}

function List-PHP-Extensions {
    param ($iniPath, $available = $false, $term = $null)

    try {
        if (-not $available) {
            $allExtensions = Get-All-PHPExtensionsStatus -iniPath $iniPath -includeIniOnly $true

            $filtered = if ($term) {
                Get-Matching-PHPExtensionsStatus -iniPath $iniPath -extName $term -includeIniOnly $true
            } else {
                $allExtensions
            }

            Display-Extensions-States -extensions $allExtensions
            Display-Installed-Extensions -extensions $filtered
        } else {
            Write-Host -Object "`nLoading available extensions..."

            $availableExtensions = Get-OrUpdateCache -cacheFileName 'available_extensions' -compute {
                return [pscustomobject] (Get-PHPExtensions-From-Source)
            }

            if ($availableExtensions.Count -eq 0) {
                Write-Host -Object "`nNo extensions found"
                return -1
            }

            $availableExtensionsPartialList = @{}
            $availableExtensions.PSObject.Properties | ForEach-Object {
                $searchResult = $_.Value
                if ($term) {
                    if ($_.Key -notlike "*$term*") {
                        # Search the list if the category doesn't match
                        $searchResult = $searchResult | Where-Object {
                            $_.extName -like "*$term*"
                        }
                    }
                }
                if ($searchResult.Count -gt 0) {
                    $availableExtensionsPartialList[$_.Name] = $searchResult
                }
            }

            if ($availableExtensionsPartialList.Count -eq 0) {
                $msg = "`nNo extensions found"
                if ($term) {
                    $msg += " matching '$term'"
                }
                Write-Host -Object $msg -ForegroundColor DarkYellow
                return -1
            }

            $maxKeyLength = ($availableExtensionsPartialList.Keys | Measure-Object -Maximum Length).Maximum
            $maxLineLength = [Math]::Max($PVMConfig.env.MIN_LINE_LENGTH, $maxKeyLength + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 3))

            Write-Host -Object "`nAvailable Extensions by Category:"
            Write-Host    '--------------------------------'
            $availableExtensionsPartialList.GetEnumerator() | Sort-Object Key | ForEach-Object {
                $key = "$($_.Key) "
                $vals = ($_.Value | ForEach-Object { $_.extName }) -join ', '

                $label = "  $key"

                $maxDescLength = (Get-Console-Width) - ($maxLineLength + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH) * 2)
                if ($maxDescLength -lt 100) { $maxDescLength = 100 }

                $descLines = @()
                $remaining = $vals
                while ($remaining.Length -gt $maxDescLength) {
                    $breakPos = $remaining.LastIndexOf(' ', $maxDescLength)
                    if ($breakPos -lt 0) { $breakPos = $maxDescLength }
                    $descLines += $remaining.Substring(0, $breakPos)
                    $remaining = $remaining.Substring($breakPos).Trim()
                }
                if ($remaining) { $descLines += $remaining }

                if ($descLines.Count -eq 0) {
                    $line = $label.PadRight($maxLineLength, '.')
                    Write-Host -Object $line
                } else {
                    $line = $label.PadRight($maxLineLength, '.') + " $($descLines[0])"
                    Write-Host -Object $line

                    $indent = ' ' * ($maxLineLength + 1)
                    for ($i = 1; $i -lt $descLines.Count; $i++) {
                        Write-Host -Object "$indent$($descLines[$i])"
                    }
                }
            }

            $msg = "`nThis is a partial list. For a complete list, visit:"
            $msg += "`nPHP Extensions : $($PVMConfig.links.peclPackages)"
            $msg += "`nXDebug : $($PVMConfig.links.xdebugHistorical)"
            Write-Host -Object $msg
        }

        return 0
    } catch {
        Write-Host -Object "`nFailed to list extensions"
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to list extensions"; exception = $_ }
        return -1
    }
}
