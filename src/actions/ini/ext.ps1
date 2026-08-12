
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
            $availableExtensionsPartialList.GetEnumerator() | Sort-Object Key | ForEach-Object -Process {
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
            $msg += "`nPHP Extensions : $($PVMConfig.links.peclPackages)"
            $msg += "`nXDebug : $($PVMConfig.links.xdebugHistorical)"
            Show-Message -message $msg
        }

        return 0
    } catch {
        Show-Error -message "`nFailed to list extensions"
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to list extensions"; exception = $_ }
        return -1
    }
}
