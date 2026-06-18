
function Get-IniSetting {
    param ($iniPath, $keys)

    try {
        if ($keys -isnot [array] -or $keys.Count -eq 0) {
            Write-Host -Object "`nPlease specify at least one setting name ('pvm ini get memory_limit')."
            return -1
        }

        $lines = Get-Content -Path $iniPath

        $overallCode = 0
        $results = [ordered]@{}
        $notFound = [ordered]@{}
        foreach ($key in $keys) {
            $pattern = '^[#;]?\s*([^=\s]*{0}[^=\s]*)\s*=\s*(.*)' -f [regex]::Escape($key)

            $result = @()
            foreach ($line in $lines) {
                if ($line -match $pattern) {
                    $item = @{
                        extensionName = $matches[1].Trim()
                        value         = $matches[2].Trim()
                        enabled       = 'Enabled'
                        color         = 'DarkGreen'
                    }

                    if ($matches[0] -match '^[#;]') {
                        $item.enabled = 'Disabled'
                        $item.color = 'DarkYellow'
                    }

                    $result += $item
                }
            }

            if ($result.Count -eq 0) {
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

            $results[$key] = $result
        }

        $results = $notFound + $results

        $maxLineLength = ($results.Values | ForEach-Object { $_ } | ForEach-Object { $_.extensionName } | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
        foreach ($key in $results.Keys) {
            Write-Host -Object "`nMatches for '$key'" -ForegroundColor Cyan

            foreach ($item in $results[$key]) {
                $extensionName = "$($item.extensionName) ".PadRight($maxLineLength, '.')
                $value = if ($item.value -eq '') { '(not set) ' } elseif ($null -eq $item.value) { '' } else { "$($item.value) " }

                Write-Host -Object "- $extensionName $value" -NoNewline
                Write-Host -Object "$($item.enabled)" -ForegroundColor $item.color
            }
        }

        return $overallCode
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get ini setting '$($keys -join ', ')'"; exception = $_ }
        return -1
    }
}
