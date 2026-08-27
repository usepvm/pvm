
function Show-PHPExtensionInfo {
    param ($iniPath, $extName)

    try {
        $normalizeId = {
            param ($name)
            if (-not $name) { return '' }
            return ([System.IO.Path]::GetFileName($name.ToString().Trim('"', "'")) -replace '^php_', '' -replace '\.dll$', '').ToLower()
        }

        New-Line
        $searchId = & $normalizeId $extName
        $linksMatchingExtName = Get-ExtensionMatchingCategories -extName $searchId
        $availableMatch = Select-ExtensionFromMatches -linksMatchingExtName $linksMatchingExtName

        $matchesListStatus = Get-MatchingPHPExtensionsStatus -iniPath $iniPath -extName $searchId -includeIniOnly $true # | Select-Object -First 1

        if ($matchesListStatus.Length -gt 1) {
            Show-Info -message "`nMultiple extensions match '$extName':`n"

            $index = 0
            $matchesListStatus | ForEach-Object -Process {
                $name = $_.name
                Show-Message -message "[$index] $name "
                $index++
            }

            do {
                $choiceRaw = Read-HostWrapper -prompt "`nSelect a number"
                $choice = $null

                if (-not [int]::TryParse($choiceRaw, [ref]$choice)) {
                    Show-Warning -message 'Please enter a valid positive number.'
                    continue
                }

                if ($choice -lt 0 -or $choice -gt $matchesListStatus.Length - 1) {
                    Show-Warning -message "Number must be between 0 and $($matchesListStatus.Length - 1)."
                    continue
                }

                break
            } while ($true)

            $localMatch = $matchesListStatus[$choice]
        } else {
            $localMatch = $($matchesListStatus)
        }

        if (-not $availableMatch -and -not $localMatch) {
            Show-Error -message "`nExtension '$extName' not found"
            return -1
        }

        Show-Info -message "`nExtension information: $extName"
        if ($availableMatch) {
            Show-Message -message "- Name ".PadRight($PVMConfig.env.MIN_LINE_LENGTH, '.') -noNewLine
            Show-Message -message " $($availableMatch.extName)"
            Show-Message -message "- Description ".PadRight($PVMConfig.env.MIN_LINE_LENGTH, '.') -noNewLine
            Show-Message -message " $(if ($availableMatch.description) { $availableMatch.description } else { '(not available)' })"
            Show-Message -message "- Category ".PadRight($PVMConfig.env.MIN_LINE_LENGTH, '.') -noNewLine
            Show-Message -message " $(if ($availableMatch.extCategory) { $availableMatch.extCategory } else { '(not available)' })"
            Show-Message -message "- Link ".PadRight($PVMConfig.env.MIN_LINE_LENGTH, '.') -noNewLine
            Show-Message -message " $(if ($availableMatch.href) { $availableMatch.href } else { '(not available)' })"
        } else {
            Show-Message -message "- Public metadata ".PadRight($PVMConfig.env.MIN_LINE_LENGTH, '.') -noNewLine
            Show-Message -message ' Not found in available extensions cache'
        }

        Show-Info -message "`nLocal installation"
        if ($localMatch) {
            Show-Message -message "- Name ".PadRight($PVMConfig.env.MIN_LINE_LENGTH, '.') -noNewLine
            Show-Message -message " $($localMatch.name)"
            Show-Message -message "- DLL name ".PadRight($PVMConfig.env.MIN_LINE_LENGTH, '.') -noNewLine
            Show-Message -message " $(if ($localMatch.fileName) { $localMatch.fileName } else { '(not found)' })"
            Show-Message -message "- Status ".PadRight($PVMConfig.env.MIN_LINE_LENGTH, '.') -noNewLine
            Write-Color -message " $($localMatch.status)" -foreColor $localMatch.color
            Show-Message -message "- INI line ".PadRight($PVMConfig.env.MIN_LINE_LENGTH, '.') -noNewLine
            Show-Message -message " $(if ($localMatch.lineNumber) { $localMatch.lineNumber } else { '(not configured)' })"
            Show-Message -message "- INI entry ".PadRight($PVMConfig.env.MIN_LINE_LENGTH, '.') -noNewLine
            Show-Message -message " $(if ($localMatch.line) { $localMatch.line } else { '(not configured)' })"
            Show-Message -message "- DLL path ".PadRight($PVMConfig.env.MIN_LINE_LENGTH, '.') -noNewLine
            Show-Message -message " $(if ($localMatch.fullPath) { $localMatch.fullPath } else { '(not found)' })"
            if ($localMatch.version) {
                Show-Message -message "- DLL version ".PadRight($PVMConfig.env.MIN_LINE_LENGTH, '.') -noNewLine
                Show-Message -message " $($localMatch.version)"
            }
            if ($localMatch.source) {
                Show-Message -message "- Source ".PadRight($PVMConfig.env.MIN_LINE_LENGTH, '.') -noNewLine
                Show-Message -message " $($localMatch.source)"
            }
            if ($localMatch.comment) {
                Show-Message -message "- Note ".PadRight($PVMConfig.env.MIN_LINE_LENGTH, '.') -noNewLine
                Show-Message -message " $($localMatch.comment)"
            }
        } else {
            Show-Message -message "- Status ".PadRight($PVMConfig.env.MIN_LINE_LENGTH, '.') -noNewLine
            Show-Message -message ' Not installed or configured locally'
        }

        return 0
    } catch {
        Show-Error -message "`nFailed to get information for extension '$extName'"
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get extension info for '$extName'"; exception = $_ }
        return -1
    }
}

function Show-PHPExtensions {
    param ($iniPath, $available = $false, $term = $null)

    try {
        if (-not $available) {
            $allExtensions = Get-AllPHPExtensionsStatus -iniPath $iniPath -includeIniOnly $true

            $filtered = if ($term) {
                Get-MatchingPHPExtensionsStatus -iniPath $iniPath -extName $term -includeIniOnly $true
            } else {
                $allExtensions
            }

            Show-ExtensionsStates -extensions $allExtensions
            Show-InstalledExtensions -extensions $filtered
        } else {
            Show-Message -message "`nLoading available extensions..."

            $availableExtensions = Get-AvailablePHPExtensions

            if ($availableExtensions.Count -eq 0) {
                Show-Error -message "`nNo extensions found"
                return -1
            }

            $availableExtensionsPartialList = Get-FilteredPHPExtensionsByCategory -availableExtensions $availableExtensions -term $term

            if ($availableExtensionsPartialList.Count -eq 0) {
                $msg = "`nNo extensions found"
                if ($term) {
                    $msg += " matching '$term'"
                }
                Show-Error -message $msg
                return -1
            }

            $maxKeyLength = ($availableExtensionsPartialList.Keys | Measure-Object -Maximum Length).Maximum
            $maxLineLength = [Math]::Max($PVMConfig.env.MIN_LINE_LENGTH, $maxKeyLength + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 3))

            Show-Info -message "`nAvailable Extensions by Category:"
            Write-Gray -message '--------------------------------'
            $availableExtensionsPartialList.GetEnumerator() | Sort-Object -Property Key | ForEach-Object -Process {
                $key = "$($_.Key) "
                $vals = ($_.Value | ForEach-Object -Process { $_.extName }) -join ', '

                $label = "  $key"

                $maxDescLength = (Get-ConsoleWidth) - ($maxLineLength + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH) * 2)
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
                    Show-Message -message $line
                } else {
                    $line = $label.PadRight($maxLineLength, '.') + " $($descLines[0])"
                    Show-Message -message $line

                    $indent = ' ' * ($maxLineLength + 1)
                    for ($i = 1; $i -lt $descLines.Count; $i++) {
                        Show-Message -message "$indent$($descLines[$i])"
                    }
                }
            }

            $msg = "`nThis is a partial list. For a complete list, visit:"
            $msg += "`n PHP Extensions : $($PVMConfig.links.peclPackages)"
            $msg += "`n XDebug : $($PVMConfig.links.xdebugHistorical)"
            Show-Info -message $msg
        }

        return 0
    } catch {
        Show-Error -message "`nFailed to list extensions"
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to list extensions"; exception = $_ }
        return -1
    }
}
