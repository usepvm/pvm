
function Enable-IniExtension {
    param ($iniPath, $extNames)

    try {
        if ($extNames -isnot [array] -or $extNames.Count -eq 0) {
            Print-Host -message "`nPlease provide at least one extension name to enable"
            return -1
        }

        $results = @()
        $overallCode = 0
        foreach ($extName in $extNames) {
            $matchesListStatus = Get-Matching-PHPExtensionsStatus -iniPath $iniPath -extName $extName

            if ($matchesListStatus.Length -eq 0) {
                $results += @{ name = $extName; status = 'Not found'; color = 'Gray' }
                $overallCode = -1
                continue
            }

            if ($matchesListStatus.Length -gt 1) {
                Print-Info -message "`nMultiple extensions match '$extName':`n"

                $maxLineLength = ($matchesListStatus.name | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
                $index = 0
                $matchesListStatus | ForEach-Object {
                    $name = "$($_.name) ".PadRight($maxLineLength, '.')
                    Print-Host -message "[$index] $name " -NoNewline
                    Print-Color -message "$($_.status)" -foreColor $_.color
                    $index++
                }

                do {
                    $choiceRaw = Read-Host -Prompt "`nSelect a number"
                    $choice = $null

                    if (-not [int]::TryParse($choiceRaw, [ref]$choice)) {
                        Print-Warning -message 'Please enter a valid positive number.'
                        continue
                    }

                    if ($choice -lt 0 -or $choice -gt $matchesListStatus.Length - 1) {
                        Print-Warning -message "Number must be between 0 and $($matchesListStatus.Length - 1)."
                        continue
                    }

                    break
                } while ($true)

                $selected = $matchesListStatus[$choice]
            } else {
                $selected = $($matchesListStatus)
            }

            if ($selected.status -eq 'Enabled') {
                # Print-Success -message "- '$($selected.name)' enabled successfully."
                $results += @{ name = $selected.name; status = 'Enabled'; color = 'DarkGreen' }
                continue
            }

            $lines = Get-Content -Path $iniPath

            $modified = $false
            $lineNumber = 0
            $newLines = $lines | ForEach-Object {
                $lineNumber++
                if ($_ -eq $selected.line -and $selected.lineNumber -eq $lineNumber -and -not $modified) {
                    $modified = $true
                    return $_ -replace '^[#;]\s*', ''
                }
                return $_
            }

            if (-not $modified) {
                # Print-Success -message "- '$($selected.name)' enabled successfully."
                $results += @{ name = $selected.name; status = 'Enabled'; color = 'DarkGreen' }
                continue
            }

            $null = Backup-IniFile -iniPath $iniPath
            Set-Content -Path $iniPath -Value $newLines -Encoding UTF8

            $results += @{ name = $selected.name; status = 'Enabled'; color = 'DarkGreen' }
            # Print-Success -message "- '$($selected.name)' enabled successfully."
        }

        $maxLineLength = ($results.name | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
        Print-Host -message "`nResults:"
        foreach ($item in $results) {
            Print-Host -message "- $($item.name) ".PadRight($maxLineLength, '.') -NoNewline
            Print-Color -message " $($item.status)" -foreColor $item.color
        }

        return $overallCode
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to enable extension '$($extNames -join ', ')'"; exception = $_ }
        return -1
    }
}
