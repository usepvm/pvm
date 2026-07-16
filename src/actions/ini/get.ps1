
function Get-IniSetting {
    param ($iniPath, $keys)

    try {
        if ($keys -isnot [array] -or $keys.Count -eq 0) {
            Print-Host -message "`nPlease specify at least one setting name ('pvm ini get memory_limit')."
            return -1
        }

        $overallCode = 0
        $results = [ordered]@{}
        $notFound = [ordered]@{}
        foreach ($key in $keys) {
            $matchesList = Get-Matching-PHPSettings -iniPath $iniPath -searchKey $key

            if ($matchesList.Count -eq 0) {
                $notFound[$key] = @(
                    @{
                        extensionName = $key
                        value         = $null
                        enabled       = 'Not Found'
                        color         = 'Gray'
                    }
                )
                $overallCode = -1
                continue
            }

            $results[$key] = $matchesList | ForEach-Object {
                @{ extensionName = $_.name; value = $_.value; enabled = $_.status; color = $_.color }
            }
        }

        $results = $notFound + $results

        $maxLineLength = ($results.Values | ForEach-Object { $_ } | ForEach-Object { $_.extensionName } | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
        foreach ($key in $results.Keys) {
            Print-Info -message "`nMatches for '$key'"

            foreach ($item in $results[$key]) {
                $extensionName = "$($item.extensionName) ".PadRight($maxLineLength, '.')
                $value = if ($item.value -eq '') { '(not set) ' } elseif ($null -eq $item.value) { '' } else { "$($item.value) " }

                Print-Host -message "- $extensionName $value" -noNewLine
                Write-Color -message "$($item.enabled)" -foreColor $item.color
            }
        }

        return $overallCode
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get ini setting '$($keys -join ', ')'"; exception = $_ }
        return -1
    }
}
